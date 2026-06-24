defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceReader do
  @moduledoc """
  Normalizes Coding PR Delivery completion-validator inputs at the adapter edge.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.CompletionValidator.ProfileDefaults
  alias SymphonyElixir.Workflow.IssueContext

  @type context :: %{
          required(:profile_context) => ProfileDefaults.resolved_profile(),
          required(:evidence) => map(),
          required(:allowed_routes) => [String.t()],
          required(:route_key) => String.t() | nil
        }

  @spec context(map(), keyword()) :: {:ok, context()} | {:error, map()}
  def context(issue, opts) when is_map(issue) and is_list(opts) do
    if Keyword.keyword?(opts) do
      context_from_keyword_opts(issue, opts)
    else
      {:error, %{code: :invalid_completion_validator_input, reason: :invalid_options}}
    end
  end

  defp context_from_keyword_opts(issue, opts) do
    with {:ok, profile_context} <- profile_context(issue, opts) do
      evidence = evidence(issue, opts)
      contract = completion_contract(issue, profile_context)

      {:ok,
       %{
         profile_context: profile_context,
         evidence: evidence,
         allowed_routes: string_list(contract_allowed_completion_routes(contract)),
         route_key: completion_route(issue, opts, evidence)
       }}
    end
  end

  @spec field(term(), atom()) :: term()
  def field(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, key) -> Map.get(map, key)
      true -> nil
    end
  end

  def field(_map, _key), do: nil

  @spec deep_field(term(), [atom()]) :: term()
  def deep_field(value, []), do: value

  def deep_field(value, [key | rest]) do
    value
    |> field(key)
    |> deep_field(rest)
  end

  @spec first_map([term()]) :: map()
  def first_map(values) when is_list(values) do
    Enum.find_value(values, %{}, fn
      value when is_map(value) -> value
      _value -> nil
    end)
  end

  @spec route_value(term(), atom()) :: String.t() | nil
  def route_value(map, key) when is_map(map) do
    map
    |> field(key)
    |> normalize_string()
  end

  def route_value(_map, _key), do: nil

  @spec truthy?(term()) :: boolean()
  def truthy?(true), do: true

  def truthy?(value) when is_binary(value),
    do: value in SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Values.truthy_strings()

  def truthy?(1), do: true
  def truthy?(_value), do: false

  @spec present_string?(term()) :: boolean()
  def present_string?(value) when is_binary(value), do: String.trim(value) != ""
  def present_string?(value) when is_integer(value), do: true
  def present_string?(_value), do: false

  @spec non_empty_list?(term()) :: boolean()
  def non_empty_list?(values) when is_list(values), do: values != []
  def non_empty_list?(_values), do: false

  @spec capability_set(term()) :: MapSet.t(String.t())
  def capability_set(%MapSet{} = values), do: values

  def capability_set(values) do
    values
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  @spec string_list(term()) :: [String.t()]
  def string_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec normalize_string(term()) :: String.t() | nil
  def normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_string(value) when is_atom(value) and not is_boolean(value),
    do: Atom.to_string(value)

  def normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_string(_value), do: nil

  defp profile_context(issue, opts) do
    issue_profile =
      issue
      |> workflow_value(Evidence.profile_key())
      |> normalize_map()

    settings_profile =
      opts
      |> opt(Evidence.settings_key())
      |> settings_profile()
      |> normalize_map()

    profile_config =
      cond do
        map_size(issue_profile) > 0 -> issue_profile
        map_size(settings_profile) > 0 -> settings_profile
        true -> ProfileDefaults.default_profile_config()
      end

    case ProfileDefaults.resolve_profile(profile_config) do
      {:ok, resolved_profile} -> {:ok, resolved_profile}
      {:error, _reason} -> {:error, %{code: :invalid_completion_validator_input, reason: :profile_not_resolved}}
    end
  end

  defp completion_contract(issue, profile_context) do
    case workflow_value(issue, Evidence.completion_contract_key()) do
      contract when is_map(contract) ->
        contract

      _contract ->
        ProfileDefaults.completion_contract(profile_context.module, profile_context.options)
    end
  end

  defp contract_allowed_completion_routes(contract) when is_map(contract),
    do: field(contract, Evidence.allowed_completion_routes_key()) || []

  defp completion_route(issue, opts, evidence) do
    opt(opts, Evidence.target_route_key()) ||
      evidence |> field(Evidence.route_key()) |> route_value(Evidence.target_key()) ||
      evidence |> field(Evidence.route_key()) |> route_value(Evidence.current_key()) ||
      evidence |> route_value(Evidence.target_route_key()) ||
      evidence |> route_value(Evidence.route_key_key()) ||
      issue_route_key(issue)
  end

  defp issue_route_key(issue) do
    case IssueContext.route_facts(issue) do
      %{route_key: route_key} when is_atom(route_key) -> Atom.to_string(route_key)
      _route_facts -> nil
    end
  end

  defp evidence(issue, opts) when is_map(issue) do
    opts_evidence = opt(opts, Evidence.evidence_key())

    cond do
      is_map(opts_evidence) ->
        opts_evidence

      is_map(workflow_value(issue, Evidence.completion_evidence_key())) ->
        workflow_value(issue, Evidence.completion_evidence_key())

      is_map(workflow_value(issue, Evidence.evidence_key())) ->
        workflow_value(issue, Evidence.evidence_key())

      true ->
        %{}
    end
  end

  defp workflow_value(issue, key) when is_map(issue) and is_atom(key) do
    issue
    |> workflow_map()
    |> field(key)
  end

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_list(opts) and is_atom(key),
    do: Keyword.get(opts, key, default)

  defp opt(_opts, _key, default), do: default

  defp settings_profile(settings) when is_map(settings) do
    settings
    |> field(Evidence.workflow_key())
    |> field(Evidence.profile_key())
  end

  defp settings_profile(_settings), do: nil

  defp workflow_map(issue) when is_map(issue) do
    case field(issue, Evidence.workflow_key()) do
      workflow when is_map(workflow) -> workflow
      _workflow -> %{}
    end
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}
end
