defmodule SymphonyElixir.ChangeProposalReconciliation.Producer.StartupBacklogBootstrap do
  @moduledoc """
  One-shot startup producer for review backlog candidates.

  Runtime-targeted reconciliation intentionally avoids broad provider scans
  during normal poll cycles. This producer bridges process restarts by doing a
  single bounded scan of the configured source routes and enqueueing those ids
  into the same runtime inbox used by webhooks, typed-tool events, and known
  target watchers.
  """

  use GenServer

  alias SymphonyElixir.ChangeProposalReconciliation.{CandidateInbox, Contract, RouteContext}
  alias SymphonyElixir.Config
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig

  @type run_result :: %{
          status: :ok | :skipped | :error,
          candidate_count: non_neg_integer(),
          enqueued_count: non_neg_integer(),
          error: String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = merge_application_opts(opts)

    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec run_once(keyword()) :: run_result()
  def run_once(opts \\ []) when is_list(opts) do
    settings_fn = Keyword.get(opts, :settings_fn, &Config.settings/0)
    config_fn = Keyword.get(opts, :config_fn, &ReconciliationConfig.from_settings/1)
    fetch_issues_fn = Keyword.get(opts, :fetch_issues_by_states_fn, &Tracker.fetch_issues_by_states/2)
    enqueue_fn = Keyword.get(opts, :enqueue_issue_ids_fn, &CandidateInbox.enqueue_issue_ids/2)
    emit_event_fn = Keyword.get(opts, :emit_event_fn, &ObservabilityLogger.emit/3)
    inbox = Keyword.get(opts, :inbox, CandidateInbox)

    started_at_ms = System.monotonic_time(:millisecond)

    with {:ok, settings} <- settings_fn.(),
         {:ok, %ReconciliationConfig{enabled?: true, candidate_discovery: :runtime_targeted} = config} <-
           config_fn.(settings),
         source_raw_states when source_raw_states != [] <- RouteContext.source_raw_states(settings, config),
         {:ok, issues} <- fetch_issues_fn.(source_raw_states, []),
         issue_ids <- candidate_issue_ids(settings, config, issues),
         {:ok, enqueue_result} <- enqueue_fn.(issue_ids, server: inbox) do
      result = %{
        status: :ok,
        candidate_count: length(issue_ids),
        enqueued_count: Map.get(enqueue_result, :accepted_count, 0),
        error: nil
      }

      emit_completed(emit_event_fn, settings, result, started_at_ms)
      result
    else
      {:ok, %ReconciliationConfig{enabled?: false}} ->
        skipped(:disabled, emit_event_fn, started_at_ms)

      {:ok, %ReconciliationConfig{candidate_discovery: discovery}} ->
        skipped({:candidate_discovery, discovery}, emit_event_fn, started_at_ms)

      [] ->
        skipped(:missing_source_routes, emit_event_fn, started_at_ms)

      {:error, reason} ->
        failed(reason, emit_event_fn, started_at_ms)

      reason ->
        failed(reason, emit_event_fn, started_at_ms)
    end
  end

  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled?, Keyword.get(opts, :enabled, true)) == true do
      {:ok, opts, {:continue, :bootstrap}}
    else
      {:ok, opts}
    end
  end

  @impl true
  def handle_continue(:bootstrap, opts) do
    _result = run_once(opts)
    {:noreply, opts}
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

  defp emit_completed(emit_event_fn, settings, result, started_at_ms) do
    emit_event_fn.(
      :info,
      :change_proposal_startup_backlog_bootstrap_completed,
      %{
        component: Contract.component(),
        producer: "startup_backlog_bootstrap",
        tracker_kind: tracker_kind(settings),
        status: Atom.to_string(result.status),
        candidate_count: result.candidate_count,
        enqueued_count: result.enqueued_count,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )
  end

  defp skipped(reason, emit_event_fn, started_at_ms) do
    emit_event_fn.(
      :info,
      :change_proposal_startup_backlog_bootstrap_completed,
      %{
        component: Contract.component(),
        producer: "startup_backlog_bootstrap",
        status: "skipped",
        skip_reason: inspect(reason),
        candidate_count: 0,
        enqueued_count: 0,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )

    %{status: :skipped, candidate_count: 0, enqueued_count: 0, error: nil}
  end

  defp failed(reason, emit_event_fn, started_at_ms) do
    error = inspect(reason)

    emit_event_fn.(
      :warning,
      :change_proposal_startup_backlog_bootstrap_completed,
      %{
        component: Contract.component(),
        producer: "startup_backlog_bootstrap",
        status: "error",
        error: error,
        candidate_count: 0,
        enqueued_count: 0,
        duration_ms: elapsed_ms(started_at_ms)
      }
    )

    %{status: :error, candidate_count: 0, enqueued_count: 0, error: error}
  end

  defp tracker_kind(%{tracker: tracker}), do: Tracker.Config.kind(tracker)
  defp tracker_kind(%{"tracker" => tracker}), do: Tracker.Config.kind(tracker)
  defp tracker_kind(_settings), do: nil

  defp elapsed_ms(started_at_ms), do: System.monotonic_time(:millisecond) - started_at_ms

  defp merge_application_opts(opts) do
    app_opts =
      :symphony_elixir
      |> Application.get_env(:change_proposal_startup_backlog_bootstrap, [])
      |> normalize_keyword()

    Keyword.merge(app_opts, opts)
  end

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(_opts), do: []
end
