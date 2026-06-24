defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Runner do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config, as: ReconciliationConfig
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Deps
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Probe
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Report
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.WorkflowRef
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.TrackerCallOptions

  @spec run(term(), term()) :: Report.t()
  def run(opts, deps) do
    with {:ok, opts} <- validate_opts(opts),
         {:ok, deps} <- Deps.validate(deps) do
      run_validated(opts, deps)
    else
      {:error, reason} ->
        invalid_report(reason)
    end
  end

  defp run_validated(opts, deps) do
    started_at_ms = deps.monotonic_time_ms.()
    previous_workflow_env = deps.workflow_file_env.()
    issue_id = opts |> Keyword.get(:issue_id) |> normalize_optional_string()
    mode = Contract.mode_from_options(opts)

    try do
      case WorkflowRef.resolve(opts, deps) do
        {:ok, workflow_path, workflow_label} ->
          :ok = deps.set_workflow_file_path.(workflow_path)

          {probes, settings, reconciliation_config} = run_config_probe(deps)

          with_known_target_registry(deps, workflow_label, issue_id, mode, started_at_ms, settings, fn known_target_registry ->
            {probes, before_issue} =
              append_issue_probe(probes, settings, issue_id, deps, Contract.probe_id(:fetch_before))

            probes = append_reconcile_probe(probes, settings, before_issue, issue_id, mode, opts, deps, known_target_registry)

            {probes, after_issue} =
              append_issue_probe(probes, settings, issue_id, deps, Contract.probe_id(:fetch_after))

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
          failure_report(issue_id, mode, Contract.probe_id(:workflow), reason, deps.monotonic_time_ms.() - started_at_ms)
      end
    after
      deps.restore_workflow_file_env.(previous_workflow_env)
    end
  end

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts}
    else
      {:error, %{code: :invalid_one_shot_options, value_type: "list"}}
    end
  end

  defp validate_opts(opts), do: {:error, %{code: :invalid_one_shot_options, value_type: Diagnostics.type_name(opts)}}

  defp invalid_report(reason) do
    failure_report(nil, Contract.mode(:invalid), Contract.probe_id(:options), reason, 0)
  end

  defp failure_report(issue_id, mode, probe_id, reason, duration_ms) do
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
      [Probe.failed(probe_id, reason)],
      duration_ms
    )
  end

  defp run_config_probe(deps) do
    {probe, result} =
      Probe.run(Contract.probe_id(:config_validation), deps.monotonic_time_ms, fn ->
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
    do: {probes ++ [Probe.failed(id, %{code: :workflow_config_unavailable})], nil}

  defp append_issue_probe(probes, settings, issue_id, deps, id) do
    {probe, result} =
      Probe.run(id, deps.monotonic_time_ms, fn ->
        with {:ok, issue_id} <- present_value(issue_id),
             {:ok, issues} <- deps.fetch_issue_states_by_ids.(settings.tracker, [issue_id], []),
             {:ok, issue} <- single_issue(issues) do
          {:ok, "issue state=#{issue_state(issue) || "unknown"}", issue}
        end
      end)

    {probes ++ [probe], Probe.ok_value(result)}
  end

  defp append_reconcile_probe(probes, nil, _before_issue, _issue_id, _mode, _opts, _deps, _known_target_registry),
    do: probes ++ [Probe.failed(Contract.probe_id(:targeted_reconcile), %{code: :workflow_config_unavailable})]

  defp append_reconcile_probe(probes, _settings, nil, _issue_id, _mode, _opts, _deps, _known_target_registry),
    do: probes ++ [Probe.failed(Contract.probe_id(:targeted_reconcile), %{code: :issue_fetch_required_before_reconciliation})]

  defp append_reconcile_probe(probes, settings, %Issue{}, issue_id, mode, opts, deps, known_target_registry) do
    {probe, _result} =
      Probe.run(Contract.probe_id(:targeted_reconcile), deps.monotonic_time_ms, fn ->
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
    _error -> probes ++ [Probe.failed(Contract.probe_id(:targeted_reconcile), %{code: :invalid_issue_payload})]
  end

  defp reconcile_opts(settings, issue_id, mode, opts, deps, known_target_registry) do
    dry_run? = mode == Contract.mode(:dry_run)
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

  defp single_issue([%Issue{} = issue]), do: {:ok, issue}
  defp single_issue([issue]) when is_map(issue), do: {:ok, struct(Issue, issue)}
  defp single_issue([]), do: {:error, %{code: :issue_not_found}}
  defp single_issue(issues) when is_list(issues), do: {:error, %{code: :unexpected_issue_count, count: length(issues)}}
  defp single_issue(_issues), do: {:error, %{code: :unexpected_issue_lookup_payload}}

  defp with_known_target_registry(_deps, _workflow_label, _issue_id, _mode, _started_at_ms, nil, fun)
       when is_function(fun, 1) do
    fun.(nil)
  end

  defp with_known_target_registry(deps, workflow_label, issue_id, mode, started_at_ms, settings, fun)
       when is_map(deps) and is_function(fun, 1) do
    case deps.start_known_target_registry.(settings) do
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
          [Probe.failed(Contract.probe_id(:known_target_registry), reason)],
          deps.monotonic_time_ms.() - started_at_ms
        )
    end
  end

  defp issue_state(%Issue{state: state}), do: normalize_optional_string(state)
  defp issue_state(issue) when is_map(issue), do: issue |> map_value(:state) |> normalize_optional_string()

  defp present_value(value) when is_binary(value), do: {:ok, value}
  defp present_value(_value), do: {:error, %{code: :issue_id_required}}

  defp map_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, Atom.to_string(key))

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
