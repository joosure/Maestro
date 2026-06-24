defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Context do
  @moduledoc """
  Runtime context projection for structured-plan review handoff.

  This module is the plugin-owned adapter boundary that accepts workflow maps,
  issue maps, runtime metadata, and structured-plan options. The policy consumes
  the normalized context instead of reading those input shapes directly.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: StructuredPlanContract

  @profile_kind_key "profile_kind"
  @profile_version_key "profile_version"
  @profile_key "profile"
  @kind_key "kind"
  @version_key "version"
  @runtime_metadata_key "runtime_metadata"
  @issue_id_key "id"
  @issue_identifier_key "identifier"
  @default_route_key "developing"
  @context_missing_reason "structured_plan_context_missing"
  @structured_plan_opts_key :structured_execution_plan
  @gates_key :gates
  @enabled_gate StructuredPlanContract.enabled_gate_key()
  @review_handoff_gate StructuredPlanContract.transition_readiness_required_gate_key()

  @type t :: %{
          optional(:run_id) => String.t(),
          optional(:issue_ids) => [String.t()],
          optional(:route_key) => String.t(),
          optional(:workflow_profile) => map()
        }

  @spec build(map() | struct() | nil, map(), keyword(), term()) :: t()
  def build(workflow, issue, opts, config) do
    %{
      run_id: option_value(config, :run_id) || Keyword.get(opts, :run_id) || runtime_value(opts, :run_id),
      issue_ids: issue_ids(issue, opts, config),
      route_key: option_value(config, :route_key) || @default_route_key,
      workflow_profile: option_value(config, :workflow_profile) || workflow_profile(workflow)
    }
  end

  @spec required(t(), atom()) :: {:ok, String.t() | map()} | {:error, map()}
  def required(context, key) do
    case Map.get(context, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      %{@kind_key => kind, @version_key => version} = profile when is_binary(kind) and is_integer(version) ->
        {:ok, profile}

      _value ->
        {:error, %{code: @context_missing_reason, missing: Atom.to_string(key)}}
    end
  end

  @spec structured_plan_opts(keyword()) :: term()
  def structured_plan_opts(opts), do: Keyword.get(opts, @structured_plan_opts_key, %{})

  @spec gate_state(keyword()) :: :enabled | :disabled | {:misconfigured, :structured_execution_plan_disabled}
  def gate_state(opts) do
    structured_enabled? = gate_enabled?(opts, @enabled_gate, :enabled)
    review_handoff_required? = gate_enabled?(opts, @review_handoff_gate, :review_handoff_required)

    cond do
      review_handoff_required? and structured_enabled? ->
        :enabled

      review_handoff_required? ->
        {:misconfigured, :structured_execution_plan_disabled}

      true ->
        :disabled
    end
  end

  @spec option_value(term(), atom() | String.t()) :: term()
  def option_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key)
  def option_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)

  def option_value(keyword, key) when is_list(keyword) and is_atom(key) do
    if Keyword.keyword?(keyword), do: Keyword.get(keyword, key), else: nil
  end

  def option_value(_config, _key), do: nil

  defp gate_enabled?(opts, gate_key, config_key) do
    gates = Keyword.get(opts, @gates_key, StructuredPlanContract.gate_defaults())
    config = structured_plan_opts(opts)

    gate_value(gates, gate_key) == true or
      option_value(config, gate_key) == true or
      option_value(config, config_key) == true
  end

  defp gate_value(gates, gate_key) when is_map(gates), do: Map.get(gates, gate_key)
  defp gate_value(_gates, _gate_key), do: nil

  defp runtime_value(opts, key) do
    runtime_metadata =
      case Keyword.get(opts, :tool_context) do
        %{runtime_metadata: metadata} when is_map(metadata) -> metadata
        %{@runtime_metadata_key => metadata} when is_map(metadata) -> metadata
        _context -> %{}
      end

    Keyword.get(opts, key) || Map.get(runtime_metadata, key)
  end

  defp issue_ids(issue, opts, config) do
    [
      option_value(config, :issue_id),
      option_value(config, :issue_identifier),
      Keyword.get(opts, :issue_key),
      string_value(issue, @issue_id_key),
      string_value(issue, @issue_identifier_key)
    ]
    |> Enum.flat_map(&present_values/1)
    |> Enum.uniq()
  end

  defp workflow_profile(workflow) do
    case {profile_kind(workflow), profile_version(workflow)} do
      {kind, version} when is_binary(kind) and is_integer(version) -> %{@kind_key => kind, @version_key => version}
      _profile -> nil
    end
  end

  defp profile_kind(%{profile_kind: kind}) when is_binary(kind), do: kind
  defp profile_kind(%{@profile_kind_key => kind}) when is_binary(kind), do: kind
  defp profile_kind(%{profile: %{kind: kind}}) when is_binary(kind), do: kind
  defp profile_kind(%{@profile_key => %{@kind_key => kind}}) when is_binary(kind), do: kind
  defp profile_kind(_workflow), do: nil

  defp profile_version(%{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{@profile_version_key => version}) when is_integer(version), do: version
  defp profile_version(%{profile: %{version: version}}) when is_integer(version), do: version
  defp profile_version(%{@profile_key => %{@version_key => version}}) when is_integer(version), do: version
  defp profile_version(workflow), do: if(profile_kind(workflow) == CodingPrDelivery.kind(), do: CodingPrDelivery.version())

  defp string_value(%{id: value}, @issue_id_key), do: normalize_string(value)
  defp string_value(%{identifier: value}, @issue_identifier_key), do: normalize_string(value)

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    map
    |> Map.get(key)
    |> normalize_string()
  end

  defp string_value(_map, _key), do: nil

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: nil

  defp present_values(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: value |> Atom.to_string() |> present_values()
  defp present_values(_value), do: []
end
