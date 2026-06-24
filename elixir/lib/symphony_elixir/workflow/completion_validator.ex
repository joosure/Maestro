defmodule SymphonyElixir.Workflow.CompletionValidator do
  @moduledoc """
  Dispatches completion evidence validation to registered workflow extensions.

  Platform code owns the stable facade and fallback envelope. Concrete
  profile-specific evidence rules belong to extension-owned validators.
  """

  alias SymphonyElixir.Workflow.Extension.Contributions
  alias SymphonyElixir.Workflow.IssueContext
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.RouteRef

  @type validation_result :: %{required(String.t()) => term()}

  @spec validate(map(), keyword() | map()) :: validation_result()
  def validate(issue, opts \\ [])

  def validate(issue, opts) when is_map(issue) do
    profile_context = profile_context(issue, opts)
    contract = completion_contract(issue, profile_context)
    allowed_routes = string_list(map_field(contract, :allowed_completion_routes))
    route_key = completion_route(issue, opts, evidence(issue, opts))

    case validator_for_profile(profile_context.kind) do
      nil -> skipped_result(profile_context, route_key, allowed_routes)
      validator -> validator.validate(issue, opts)
    end
  end

  def validate(_issue, _opts), do: validate(%{}, [])

  @spec merge_gate(map(), map()) :: validation_result()
  def merge_gate(evidence, capabilities \\ %{})

  def merge_gate(evidence, capabilities) when is_map(evidence) and is_map(capabilities) do
    case merge_gate_validator() do
      nil -> empty_gate_result()
      validator -> validator.merge_gate(evidence, capabilities)
    end
  end

  def merge_gate(_evidence, capabilities) when is_map(capabilities),
    do: merge_gate(%{}, capabilities)

  def merge_gate(evidence, _capabilities) when is_map(evidence), do: merge_gate(evidence, %{})
  def merge_gate(_evidence, _capabilities), do: merge_gate(%{}, %{})

  defp validator_for_profile(profile_kind) when is_binary(profile_kind) do
    Enum.find(completion_validators(), fn validator ->
      function_exported?(validator, :profile_kind, 0) and validator.profile_kind() == profile_kind
    end)
  end

  defp merge_gate_validator do
    Enum.find(completion_validators(), &function_exported?(&1, :merge_gate, 2))
  end

  defp completion_validators do
    :completion_validators
    |> Contributions.list!()
    |> Enum.filter(&validator_module?/1)
  end

  defp validator_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :profile_kind, 0) and
      function_exported?(module, :validate, 2)
  end

  defp validator_module?(_module), do: false

  defp skipped_result(profile_context, route_key, allowed_routes) do
    %{
      ReadinessContract.status_key() => ReadinessContract.skipped(),
      ReadinessContract.allowed_completion_routes_key() => allowed_routes,
      ReadinessContract.checks_key() => [],
      ReadinessContract.missing_evidence_key() => [],
      ReadinessContract.observed_evidence_key() => []
    }
    |> Map.merge(route_ref_fields(profile_context, route_key))
  end

  defp empty_gate_result do
    %{
      ReadinessContract.status_key() => ReadinessContract.skipped(),
      ReadinessContract.checks_key() => [],
      ReadinessContract.missing_evidence_key() => [],
      ReadinessContract.observed_evidence_key() => []
    }
  end

  defp route_ref_fields(profile_context, route_key) do
    case RouteRef.new(profile_context, route_key) do
      {:ok, route_ref} -> RouteRef.string_fields(route_ref)
      {:error, _reason} -> RouteRef.string_fields(profile_context, route_key)
    end
  end

  defp profile_context(issue, opts) do
    issue_profile = issue |> workflow_value(:profile) |> normalize_map()

    settings_profile =
      opts |> opt(:settings) |> map_field(:workflow) |> map_field(:profile) |> normalize_map()

    profile_config =
      cond do
        map_size(issue_profile) > 0 -> issue_profile
        map_size(settings_profile) > 0 -> settings_profile
        true -> ProfileRegistry.default_profile_config()
      end

    case ProfileRegistry.resolve(profile_config) do
      {:ok, resolved_profile} -> resolved_profile
      {:error, _reason} -> ProfileRegistry.resolve!(nil)
    end
  end

  defp completion_contract(issue, profile_context) do
    case workflow_value(issue, :completion_contract) do
      contract when is_map(contract) ->
        contract

      _contract ->
        ProfileRegistry.completion_contract(profile_context.module, profile_context.options)
    end
  end

  defp completion_route(issue, opts, evidence) do
    opt(opts, :target_route) ||
      evidence |> map_field(:route) |> route_value(:target) ||
      evidence |> map_field(:route) |> route_value(:current) ||
      evidence |> route_value(:target_route) ||
      evidence |> route_value(:route_key) ||
      issue_route_key(issue)
  end

  defp issue_route_key(issue) do
    case IssueContext.route_facts(issue) do
      %{route_key: route_key} when is_atom(route_key) -> Atom.to_string(route_key)
      _route_facts -> nil
    end
  end

  defp evidence(issue, opts) when is_map(issue) do
    opts_evidence = opt(opts, :evidence)

    cond do
      is_map(opts_evidence) -> opts_evidence
      is_map(workflow_value(issue, :completion_evidence)) -> workflow_value(issue, :completion_evidence)
      is_map(workflow_value(issue, :evidence)) -> workflow_value(issue, :evidence)
      true -> %{}
    end
  end

  defp workflow_value(issue, key) when is_map(issue) and is_atom(key) do
    issue
    |> map_field(:workflow)
    |> map_field(key)
  end

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_list(opts) and is_atom(key),
    do: Keyword.get(opts, key, default)

  defp opt(opts, key, default) when is_map(opts) and is_atom(key),
    do: map_field(opts, key) || default

  defp opt(_opts, _key, default), do: default

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp string_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp route_value(map, key) when is_map(map) do
    map
    |> map_field(key)
    |> normalize_string()
  end

  defp route_value(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value) and not is_boolean(value),
    do: Atom.to_string(value)

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(_value), do: nil
end
