defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Runs do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [blank_to_nil: 1, probe_result: 9, summarize_output: 2]

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.{Args, Runtime, Settings}

  @spec wait_for_runs(nil | String.t(), map(), map(), map()) :: {map(), String.t() | nil}
  def wait_for_runs(provider_override, context, cli_deps, deps) do
    started_at_ms = deps.monotonic_time_ms.()
    argv = Args.provider_argv(provider_override, ["run-list", "--branch", context.head, "--json", "id,event,status,url"])
    do_wait_for_runs(argv, context, cli_deps, deps, started_at_ms)
  end

  @spec run_view_log(nil | String.t(), String.t(), map(), map()) :: map()
  def run_view_log(provider_override, run_id, cli_deps, deps) do
    argv = Args.provider_argv(provider_override, ["run-view", run_id, "--log"])
    started_at_ms = deps.monotonic_time_ms.()
    expected = "repo-provider probe pull_request"
    do_wait_for_run_view_log(argv, run_id, expected, cli_deps, deps, started_at_ms)
  end

  defp do_wait_for_runs(argv, context, cli_deps, deps, started_at_ms) do
    {stdout, stderr, exit_code} = deps.cli_evaluate.(argv, cli_deps)

    cond do
      exit_code != 0 ->
        {probe_result("run-list", argv, started_at_ms, deps, false, exit_code, stdout, stderr, summarize_output(stdout, stderr)), nil}

      true ->
        case Jason.decode(stdout) do
          {:ok, runs} when is_list(runs) ->
            handle_run_list_payload(runs, argv, context, cli_deps, deps, started_at_ms, stdout, stderr)

          {:ok, _other} ->
            summary = "Expected run-list to return a JSON array"
            {probe_result("run-list", argv, started_at_ms, deps, false, 1, stdout, stderr, summary), nil}

          {:error, reason} ->
            summary = "Failed to decode run-list JSON: #{Exception.message(reason)}"
            {probe_result("run-list", argv, started_at_ms, deps, false, 1, stdout, stderr, summary), nil}
        end
    end
  end

  defp handle_run_list_payload(runs, argv, context, cli_deps, deps, started_at_ms, stdout, stderr) do
    case select_pull_request_run(runs) do
      {:ok, run_id, events} ->
        summary = "observed events=#{Enum.join(events, ",")} selected_run=#{run_id}"
        {probe_result("run-list", argv, started_at_ms, deps, true, 0, stdout, stderr, summary), run_id}

      {:wait, events} ->
        if deps.monotonic_time_ms.() - started_at_ms >= Settings.timeout_ms() do
          summary =
            "Timed out waiting for CNB push and pull_request runs for #{context.head}; observed events=#{Enum.join(events, ",")}"

          {probe_result("run-list", argv, started_at_ms, deps, false, 1, stdout, stderr, summary), nil}
        else
          Runtime.sleep_ms(deps, Settings.poll_interval_ms())
          do_wait_for_runs(argv, context, cli_deps, deps, started_at_ms)
        end
    end
  end

  defp do_wait_for_run_view_log(argv, run_id, expected, cli_deps, deps, started_at_ms) do
    {stdout, stderr, exit_code} = deps.cli_evaluate.(argv, cli_deps)

    cond do
      exit_code != 0 ->
        probe_result(
          "run-view-log",
          argv,
          started_at_ms,
          deps,
          false,
          exit_code,
          stdout,
          stderr,
          summarize_output(stdout, stderr)
        )

      String.contains?(stdout, expected) ->
        probe_result("run-view-log", argv, started_at_ms, deps, true, 0, stdout, stderr, "validated CNB stage logs for #{run_id}")

      deps.monotonic_time_ms.() - started_at_ms >= Settings.timeout_ms() ->
        probe_result(
          "run-view-log",
          argv,
          started_at_ms,
          deps,
          false,
          1,
          stdout,
          stderr,
          "Timed out waiting for run-view --log output to contain #{inspect(expected)}"
        )

      true ->
        Runtime.sleep_ms(deps, Settings.poll_interval_ms())
        do_wait_for_run_view_log(argv, run_id, expected, cli_deps, deps, started_at_ms)
    end
  end

  defp select_pull_request_run(runs) do
    events =
      runs
      |> Enum.map(&run_event/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case Enum.find(runs, &(run_event(&1) == "pull_request")) do
      nil ->
        {:wait, events}

      run ->
        if "push" in events do
          case run_id(run) do
            nil -> {:wait, events}
            id -> {:ok, id, events}
          end
        else
          {:wait, events}
        end
    end
  end

  defp run_event(run) when is_map(run) do
    run
    |> Map.get("event")
    |> blank_to_nil()
  end

  defp run_id(run) when is_map(run) do
    run
    |> Map.get("id")
    |> blank_to_nil()
  end
end
