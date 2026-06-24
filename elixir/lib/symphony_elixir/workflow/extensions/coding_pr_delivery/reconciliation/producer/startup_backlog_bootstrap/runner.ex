defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Runner do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.RouteContext

  @type run_result :: Events.run_result()

  @spec run_once(keyword()) :: run_result()
  def run_once(opts) do
    started_at_ms = System.monotonic_time(:millisecond)

    case Options.deps(opts) do
      {:ok, deps} ->
        run_once(deps, started_at_ms)

      {:error, reason} ->
        Events.failed(reason, &Defaults.emit_event/3, started_at_ms)
    end
  end

  defp run_once(deps, started_at_ms) when is_map(deps) do
    with {:ok, settings} <- deps.settings_fn.(),
         {:ok, %ReconciliationConfig{enabled?: true, candidate_discovery: :runtime_targeted} = config} <-
           deps.config_fn.(settings),
         source_raw_states when source_raw_states != [] <- RouteContext.source_raw_states(settings, config),
         {:ok, issues} <- deps.fetch_issues_fn.(source_raw_states, []),
         issue_ids <- candidate_issue_ids(settings, config, issues),
         {:ok, enqueue_result} <- deps.enqueue_fn.(issue_ids, server: deps.inbox) do
      result = %{
        status: :ok,
        candidate_count: length(issue_ids),
        enqueued_count: Map.get(enqueue_result, :accepted_count, 0),
        error: nil
      }

      Events.completed(deps.emit_event_fn, settings, result, started_at_ms)
    else
      {:ok, %ReconciliationConfig{enabled?: false}} ->
        Events.skipped(:disabled, deps.emit_event_fn, started_at_ms)

      {:ok, %ReconciliationConfig{candidate_discovery: discovery}} ->
        Events.skipped({:candidate_discovery, discovery}, deps.emit_event_fn, started_at_ms)

      [] ->
        Events.skipped(:missing_source_routes, deps.emit_event_fn, started_at_ms)

      {:error, reason} ->
        Events.failed(reason, deps.emit_event_fn, started_at_ms)

      reason ->
        Events.failed(reason, deps.emit_event_fn, started_at_ms)
    end
  end

  defp candidate_issue_ids(settings, config, issues) when is_list(issues) do
    issues
    |> Enum.flat_map(fn
      %Issue{id: issue_id} = issue when is_binary(issue_id) ->
        if source_route_issue?(settings, config, issue), do: [issue_id], else: []

      _issue ->
        []
    end)
    |> Enum.uniq()
    |> Enum.take(config.max_processed_candidate_issues_per_cycle)
  end

  defp source_route_issue?(settings, config, %Issue{} = issue) do
    context = RouteContext.for_issue(settings, issue)

    case RouteContext.route_facts(issue, context) do
      %{route_key: route_key} -> ReconciliationConfig.source_route?(config, route_key)
      _route_facts -> false
    end
  end
end
