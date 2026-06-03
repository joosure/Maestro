defmodule SymphonyElixir.ChangeProposalReconciliation.OneShot do
  @moduledoc """
  Operator one-shot entrypoint for targeted change-proposal reconciliation.

  The runner never discovers candidates by scanning a source route. It processes
  only the explicit issue id supplied by the operator and uses dry-run mode
  unless tracker writes are explicitly confirmed.
  """

  alias SymphonyElixir.ChangeProposalReconciliation
  alias SymphonyElixir.ChangeProposalReconciliation.KnownTarget
  alias SymphonyElixir.ChangeProposalReconciliation.OneShot.Probe
  alias SymphonyElixir.ChangeProposalReconciliation.OneShot.Report
  alias SymphonyElixir.ChangeProposalReconciliation.TrackerCallOptions
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Templates

  @type probe_result :: Report.probe_result()
  @type report :: Report.t()

  @type deps :: %{
          required(:monotonic_time_ms) => (-> integer()),
          required(:workflow_file_path) => (-> Path.t()),
          required(:set_workflow_file_path) => (Path.t() -> :ok),
          required(:workflow_file_env) => (-> {:ok, Path.t()} | :error),
          required(:restore_workflow_file_env) => ({:ok, Path.t()} | :error -> :ok),
          required(:start_known_target_registry) => (-> GenServer.on_start()),
          required(:stop_known_target_registry) => (pid() -> :ok),
          required(:resolve_template) => (String.t() -> {:ok, Path.t()} | {:error, String.t()}),
          required(:file_regular?) => (Path.t() -> boolean()),
          required(:validate_config) => (-> :ok | {:error, term()}),
          required(:settings) => (-> map()),
          required(:initial_state) => (map() -> map()),
          required(:reconcile) => (map(), map(), keyword() -> map()),
          required(:fetch_issue_states_by_ids) => (map(), [String.t()], keyword() -> {:ok, [term()]} | {:error, term()}),
          required(:update_issue_state) => (map(), String.t(), String.t(), keyword() -> :ok | {:error, term()}),
          required(:issue_events) => (String.t() -> [map()]),
          required(:recent_events) => (-> [map()])
        }

  @spec run(keyword(), deps()) :: report()
  def run(opts, deps \\ runtime_deps()) when is_list(opts) and is_map(deps) do
    started_at_ms = deps.monotonic_time_ms.()
    previous_workflow_env = deps.workflow_file_env.()
    issue_id = opts |> Keyword.get(:issue_id) |> normalize_optional_string()
    mode = run_mode(opts)

    try do
      case resolve_workflow(opts, deps) do
        {:ok, workflow_path, workflow_label} ->
          :ok = deps.set_workflow_file_path.(workflow_path)

          with_known_target_registry(deps, workflow_label, issue_id, mode, started_at_ms, fn known_target_registry ->
            {probes, settings, reconciliation_config} = run_config_probe(deps)
            {probes, before_issue} = append_issue_probe(probes, settings, issue_id, deps, "fetch-before")
            probes = append_reconcile_probe(probes, settings, before_issue, issue_id, mode, opts, deps, known_target_registry)
            {probes, after_issue} = append_issue_probe(probes, settings, issue_id, deps, "fetch-after")

            Report.build(
              workflow_label,
              issue_id,
              settings,
              reconciliation_config,
              mode,
              before_issue,
              after_issue,
              deps.issue_events.(issue_id || ""),
              deps.recent_events.(),
              probes,
              deps.monotonic_time_ms.() - started_at_ms
            )
          end)

        {:error, reason} ->
          Report.build(
            nil,
            issue_id,
            nil,
            nil,
            mode,
            nil,
            nil,
            [],
            [],
            [Probe.failed("workflow", reason)],
            deps.monotonic_time_ms.() - started_at_ms
          )
      end
    after
      deps.restore_workflow_file_env.(previous_workflow_env)
    end
  end

  @spec format_text(report()) :: String.t()
  defdelegate format_text(report), to: Report

  @spec to_map(report()) :: map()
  defdelegate to_map(report), to: Report

  @spec runtime_deps() :: deps()
  def runtime_deps do
    %{
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      workflow_file_path: &Workflow.workflow_file_path/0,
      set_workflow_file_path: &Workflow.set_workflow_file_path/1,
      workflow_file_env: fn -> Application.fetch_env(:symphony_elixir, :workflow_file_path) end,
      restore_workflow_file_env: &restore_workflow_file_env/1,
      start_known_target_registry: fn -> KnownTarget.Registry.start_link(name: nil) end,
      stop_known_target_registry: fn pid ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        :ok
      end,
      resolve_template: &Templates.resolve/1,
      file_regular?: &File.regular?/1,
      validate_config: &SymphonyElixir.Config.validate!/0,
      settings: &SymphonyElixir.Config.settings!/0,
      initial_state: fn settings -> State.initial(config: settings) end,
      reconcile: &ChangeProposalReconciliation.reconcile/3,
      fetch_issue_states_by_ids: fn tracker, issue_ids, fetch_opts ->
        Tracker.fetch_issue_states_by_ids(tracker, issue_ids, fetch_opts)
      end,
      update_issue_state: fn tracker, issue_id, state_name, update_opts ->
        Tracker.update_issue_state(tracker, issue_id, state_name, update_opts)
      end,
      issue_events: fn issue_id -> EventStore.recent_issue_events(%{issue_id: issue_id}, limit: 50) end,
      recent_events: fn -> EventStore.recent_events(limit: 50) end
    }
  end

  defp resolve_workflow(opts, deps) do
    template = opts |> Keyword.get(:template) |> normalize_optional_string()
    workflow_path = opts |> Keyword.get(:workflow_path) |> normalize_optional_string()

    cond do
      is_binary(template) ->
        with {:ok, path} <- deps.resolve_template.(template) do
          {:ok, path, "template:#{template}"}
        end

      is_binary(workflow_path) ->
        expanded = Path.expand(workflow_path)

        if deps.file_regular?.(expanded) do
          {:ok, expanded, expanded}
        else
          {:error, "Workflow file not found: #{expanded}"}
        end

      true ->
        path = deps.workflow_file_path.()

        if deps.file_regular?.(path) do
          {:ok, path, path}
        else
          {:error, "Workflow file not found: #{path}"}
        end
    end
  end

  defp run_config_probe(deps) do
    {probe, result} =
      Probe.run("config-validation", deps.monotonic_time_ms, fn ->
        with :ok <- deps.validate_config.(),
             settings = deps.settings.(),
             {:ok, %ReconciliationConfig{enabled?: true} = config} <- ReconciliationConfig.from_settings(settings) do
          {:ok, "change proposal reconciliation enabled", {settings, config}}
        else
          {:ok, %ReconciliationConfig{enabled?: false}} ->
            {:error, "change proposal reconciliation is disabled"}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    case result do
      {:ok, {settings, config}} -> {[probe], settings, config}
      _result -> {[probe], nil, nil}
    end
  end

  defp append_issue_probe(probes, nil, _issue_id, _deps, id),
    do: {probes ++ [Probe.failed(id, "workflow config unavailable")], nil}

  defp append_issue_probe(probes, settings, issue_id, deps, id) do
    {probe, result} =
      Probe.run(id, deps.monotonic_time_ms, fn ->
        with {:ok, issue_id} <- present_value(issue_id, "issue id is required"),
             {:ok, issues} <- deps.fetch_issue_states_by_ids.(settings.tracker, [issue_id], []),
             {:ok, issue} <- single_issue(issues, issue_id) do
          {:ok, "issue #{issue_id} state=#{issue_state(issue) || "unknown"}", issue}
        end
      end)

    {probes ++ [probe], Probe.ok_value(result)}
  end

  defp append_reconcile_probe(probes, nil, _before_issue, _issue_id, _mode, _opts, _deps, _known_target_registry),
    do: probes ++ [Probe.failed("targeted-reconcile", "workflow config unavailable")]

  defp append_reconcile_probe(probes, _settings, nil, _issue_id, _mode, _opts, _deps, _known_target_registry),
    do: probes ++ [Probe.failed("targeted-reconcile", "issue fetch must pass before reconciliation")]

  defp append_reconcile_probe(probes, settings, %Issue{}, issue_id, mode, opts, deps, known_target_registry) do
    {probe, _result} =
      Probe.run("targeted-reconcile", deps.monotonic_time_ms, fn ->
        state = deps.initial_state.(settings)
        reconcile_opts = reconcile_opts(settings, issue_id, mode, opts, deps, known_target_registry)
        _state = deps.reconcile.(settings, state, reconcile_opts)
        {:ok, "targeted reconciliation completed mode=#{mode}", :ok}
      end)

    probes ++ [probe]
  end

  defp append_reconcile_probe(probes, settings, issue, issue_id, mode, opts, deps, known_target_registry) when is_map(issue) do
    append_reconcile_probe(probes, settings, struct(Issue, issue), issue_id, mode, opts, deps, known_target_registry)
  rescue
    _error -> probes ++ [Probe.failed("targeted-reconcile", "issue fetch returned an invalid issue payload")]
  end

  defp reconcile_opts(settings, issue_id, mode, opts, deps, known_target_registry) do
    dry_run? = mode == "dry_run"
    update_issue_state = update_issue_state_fun(settings, dry_run?, deps)

    opts
    |> TrackerCallOptions.fetch()
    |> Keyword.merge(
      targeted_issue_ids: [issue_id],
      known_target_registry: known_target_registry,
      dry_run?: dry_run?,
      fetch_issues_by_states_fn: fn _states, _fetch_opts ->
        {:error, :operator_one_shot_source_route_scan_forbidden}
      end,
      fetch_issue_states_by_ids_fn: fn issue_ids, fetch_opts ->
        deps.fetch_issue_states_by_ids.(settings.tracker, issue_ids, fetch_opts)
      end,
      update_issue_state_fn: update_issue_state
    )
  end

  defp update_issue_state_fun(_settings, true, _deps) do
    fn _issue_id, _state_name, _update_opts -> {:error, :dry_run_state_write_blocked} end
  end

  defp update_issue_state_fun(settings, false, deps) do
    fn issue_id, state_name, update_opts ->
      deps.update_issue_state.(settings.tracker, issue_id, state_name, update_opts)
    end
  end

  defp single_issue([%Issue{} = issue], _issue_id), do: {:ok, issue}
  defp single_issue([issue], _issue_id) when is_map(issue), do: {:ok, struct(Issue, issue)}
  defp single_issue([], issue_id), do: {:error, "issue not found: #{issue_id}"}
  defp single_issue(issues, issue_id) when is_list(issues), do: {:error, "expected one issue for #{issue_id}, got #{length(issues)}"}
  defp single_issue(_issues, issue_id), do: {:error, "unexpected issue lookup payload for #{issue_id}"}

  defp run_mode(opts) do
    if Keyword.get(opts, :confirm_state_write, false), do: "state_write", else: "dry_run"
  end

  defp with_known_target_registry(deps, workflow_label, issue_id, mode, started_at_ms, fun)
       when is_map(deps) and is_function(fun, 1) do
    case deps.start_known_target_registry.() do
      {:ok, pid} when is_pid(pid) ->
        try do
          fun.(pid)
        after
          deps.stop_known_target_registry.(pid)
        end

      {:error, {:already_started, pid}} when is_pid(pid) ->
        fun.(pid)

      {:error, reason} ->
        Report.build(
          workflow_label,
          issue_id,
          nil,
          nil,
          mode,
          nil,
          nil,
          [],
          [],
          [Probe.failed("known-target-registry", reason)],
          deps.monotonic_time_ms.() - started_at_ms
        )
    end
  end

  defp issue_state(%Issue{state: state}), do: normalize_optional_string(state)
  defp issue_state(issue) when is_map(issue), do: issue |> map_value(:state) |> normalize_optional_string()

  defp present_value(value, _message) when is_binary(value), do: {:ok, value}
  defp present_value(_value, message), do: {:error, message}

  defp restore_workflow_file_env({:ok, path}) when is_binary(path), do: Workflow.set_workflow_file_path(path)
  defp restore_workflow_file_env(:error), do: Workflow.clear_workflow_file_path()

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: value |> Integer.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil
end
