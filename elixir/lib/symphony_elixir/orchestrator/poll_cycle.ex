defmodule SymphonyElixir.Orchestrator.PollCycle do
  @moduledoc false

  alias SymphonyElixir.Config
  alias SymphonyElixir.Orchestrator.Events
  alias SymphonyElixir.Orchestrator.IssueDispatch
  alias SymphonyElixir.Orchestrator.Polling
  alias SymphonyElixir.Orchestrator.Running
  alias SymphonyElixir.Orchestrator.Runtime
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Error, as: TrackerError

  @poll_transition_render_delay_ms 20

  @spec schedule_initial_poll(State.t(), keyword()) :: State.t()
  def schedule_initial_poll(%State{} = state, opts) do
    if Keyword.get(opts, :schedule_initial_poll?, true) do
      Polling.schedule_tick(state, 0)
    else
      state
    end
  end

  @spec begin(State.t(), keyword()) :: State.t()
  def begin(%State{} = state, opts) do
    state = refresh_runtime_config(state)
    state = Polling.begin_poll_check(state)

    Events.emit_poll_cycle(:info, :poll_cycle_started, state)
    notify_dashboard(opts)
    :ok = Polling.schedule_poll_cycle_start(@poll_transition_render_delay_ms)
    state
  end

  @spec run(State.t(), keyword()) :: State.t()
  def run(%State{} = state, opts) do
    state = refresh_runtime_config(state)
    started_at_ms = System.monotonic_time(:millisecond)
    {state, poll_status, poll_extra_fields} = dispatch(state, opts)
    state = Polling.schedule_tick(state, state.poll_interval_ms)
    state = %{state | poll_check_in_progress: false}

    Events.emit_poll_cycle(
      poll_status,
      :poll_cycle_completed,
      state,
      Map.put(poll_extra_fields, :duration_ms, Polling.elapsed_ms(started_at_ms))
    )

    notify_dashboard(opts)
    state
  end

  @spec refresh_runtime_config(State.t()) :: State.t()
  def refresh_runtime_config(%State{} = state) do
    Polling.refresh_runtime_config(state, Config.settings!())
  end

  defp dispatch(%State{} = state, opts) do
    state = reconcile_running_issues(state, opts)

    with :ok <- Config.validate!(),
         {:ok, issues} <- Tracker.fetch_candidate_issues() do
      if Events.available_slots(state) > 0 do
        {IssueDispatch.choose_issues(issues, state), :info, %{status: "ok", candidate_count: length(issues)}}
      else
        {state, :info, %{status: "ok", candidate_count: length(issues), skip_reason: "no_orchestrator_slots"}}
      end
    else
      {:error, :missing_tracker_kind} ->
        Events.emit_config_validation_failed(:missing_tracker_kind)
        {state, :error, %{status: "config_error", error: inspect(:missing_tracker_kind)}}

      {:error, {:unsupported_tracker_kind, kind}} ->
        Events.emit_config_validation_failed({:unsupported_tracker_kind, kind})
        {state, :error, %{status: "config_error", error: inspect({:unsupported_tracker_kind, kind})}}

      {:error, %TrackerError{operation: :validate_config} = error} ->
        Events.emit_config_validation_failed(error)
        {state, :error, %{status: "config_error", error: error.message || inspect(error)}}

      {:error, %RepoProviderError{operation: :validate_config} = error} ->
        Events.emit_config_validation_failed(error)
        {state, :error, %{status: "config_error", error: error.message || inspect(error)}}

      {:error, {:invalid_workflow_config, message}} ->
        Events.emit_config_validation_failed({:invalid_workflow_config, message})
        {state, :error, %{status: "config_error", error: inspect({:invalid_workflow_config, message})}}

      {:error, {:missing_workflow_file, path, reason}} ->
        Events.emit_config_validation_failed({:missing_workflow_file, path, reason})
        {state, :error, %{status: "config_error", error: inspect({:missing_workflow_file, path, reason})}}

      {:error, :workflow_front_matter_not_a_map} ->
        Events.emit_config_validation_failed(:workflow_front_matter_not_a_map)
        {state, :error, %{status: "config_error", error: inspect(:workflow_front_matter_not_a_map)}}

      {:error, {:workflow_parse_error, reason}} ->
        Events.emit_config_validation_failed({:workflow_parse_error, reason})
        {state, :error, %{status: "config_error", error: inspect({:workflow_parse_error, reason})}}

      {:error, %TrackerError{} = error} ->
        Events.emit_tracker_candidate_fetch_failed(state, error)
        {state, :error, %{status: "tracker_error", error: error.message || inspect(error)}}

      {:error, reason} ->
        Events.emit_tracker_candidate_fetch_failed(state, reason)
        {state, :error, %{status: "tracker_error", error: inspect(reason)}}
    end
  end

  defp reconcile_running_issues(%State{} = state, opts) do
    state =
      Running.reconcile_stalled(
        state,
        Runtime.agent_provider_timeout_option("stall_timeout_ms", 300_000),
        running_opts(opts, nil)
      )

    running_ids = Map.keys(state.running)
    dispatch_context = Runtime.dispatch_context()

    if running_ids == [] do
      state
    else
      case Tracker.fetch_issue_states_by_ids(running_ids) do
        {:ok, issues} ->
          Running.reconcile_issue_states(issues, state, dispatch_context, running_opts(opts, state))

        {:error, reason} ->
          Events.emit_reconcile_refresh_failed(state, reason)
          state
      end
    end
  end

  defp running_opts(opts, state) do
    case Keyword.get(opts, :running_opts) do
      running_opts when is_function(running_opts, 1) -> running_opts.(state)
      _other -> []
    end
  end

  defp notify_dashboard(opts) do
    case Keyword.get(opts, :notify_dashboard) do
      notify_dashboard when is_function(notify_dashboard, 0) -> notify_dashboard.()
      _other -> :ok
    end
  end
end
