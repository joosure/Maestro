defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Parser do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Routes

  @spec parse(map(), map()) :: {:ok, Config.t()} | {:error, term()}
  def parse(attrs, profile_context) when is_map(attrs) do
    candidates = section_attrs(attrs, :candidates)
    gates = section_attrs(attrs, :gates)
    outcome_routes_attrs = section_attrs(attrs, :outcome_routes)
    thresholds = section_attrs(attrs, :thresholds)

    with {:ok, enabled?} <-
           boolean_field(attrs, Contract.field_key(:enabled), Contract.default(:enabled)),
         {:ok, candidate_discovery} <-
           candidate_discovery_field(
             candidates,
             Contract.field_key(:candidate_discovery),
             Contract.field_path(:candidate_discovery)
           ),
         {:ok, source_routes} <-
           Routes.route_list_field(
             candidates,
             Contract.field_key(:source_routes),
             profile_context,
             Contract.field_path(:source_routes)
           ),
         {:ok, outcome_routes} <- Routes.outcome_routes_field(outcome_routes_attrs, profile_context),
         {:ok, require_approval?} <-
           boolean_field(
             gates,
             Contract.field_key(:approval_required),
             Contract.default(:require_approval),
             Contract.field_path(:approval_required)
           ),
         {:ok, require_passing_checks?} <-
           boolean_field(
             gates,
             Contract.field_key(:passing_checks_required),
             Contract.default(:require_passing_checks),
             Contract.field_path(:passing_checks_required)
           ),
         {:ok, require_mergeable?} <-
           boolean_field(
             gates,
             Contract.field_key(:mergeable_required),
             Contract.default(:require_mergeable),
             Contract.field_path(:mergeable_required)
           ),
         {:ok, failed_checks_confirmation_count} <-
           positive_integer_field(
             thresholds,
             Contract.field_key(:failed_checks_confirmation_count),
             Contract.default(:failed_checks_confirmation_count),
             Contract.field_path(:failed_checks_confirmation_count)
           ),
         {:ok, max_processed_candidate_issues_per_cycle} <-
           positive_integer_field(
             candidates,
             Contract.field_key(:max_processed_issues_per_cycle),
             Contract.default(:max_processed_issues_per_cycle),
             Contract.field_path(:max_processed_issues_per_cycle)
           ),
         :ok <- validate_processed_issues_limit(max_processed_candidate_issues_per_cycle) do
      {:ok,
       %Config{
         enabled?: enabled?,
         candidate_discovery: candidate_discovery,
         source_routes: source_routes,
         outcome_routes: outcome_routes,
         require_approval?: require_approval?,
         require_passing_checks?: require_passing_checks?,
         require_mergeable?: require_mergeable?,
         failed_checks_confirmation_count: failed_checks_confirmation_count,
         max_processed_candidate_issues_per_cycle: max_processed_candidate_issues_per_cycle
       }}
    end
  end

  defp section_attrs(attrs, section) when is_map(attrs) and is_atom(section) do
    case map_value(attrs, Contract.section_key(section)) do
      section_attrs when is_map(section_attrs) -> section_attrs
      _value -> %{}
    end
  end

  defp candidate_discovery_field(attrs, key, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, Contract.default(:candidate_discovery)}

      value when is_binary(value) ->
        normalized =
          value
          |> String.trim()
          |> String.downcase()

        case Contract.candidate_discovery_mode(normalized) do
          nil ->
            {:error, {:invalid_candidate_discovery, field_path, value, Contract.candidate_discovery_modes()}}

          mode ->
            {:ok, mode}
        end

      value ->
        {:error, {:invalid_candidate_discovery, field_path, value, Contract.candidate_discovery_modes()}}
    end
  end

  defp boolean_field(attrs, key, default, field_path \\ nil) when is_map(attrs) and is_binary(key) do
    field_path = field_path || key

    case map_value(attrs, key) do
      nil -> {:ok, default}
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, {:invalid_boolean, field_path, value}}
    end
  end

  defp positive_integer_field(attrs, key, default, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_positive_integer, field_path, value}}
    end
  end

  defp validate_processed_issues_limit(value) do
    limit = Contract.max_processed_issues_per_cycle_limit()

    if value <= limit do
      :ok
    else
      {:error, {:max_processed_issues_per_cycle_too_large, Contract.field_path(:max_processed_issues_per_cycle), value, limit}}
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil
end
