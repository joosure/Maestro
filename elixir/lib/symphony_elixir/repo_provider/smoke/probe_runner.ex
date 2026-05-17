defmodule SymphonyElixir.RepoProvider.Smoke.ProbeRunner do
  @moduledoc """
  Probe execution engine for repo-provider smoke tests.

  Provides primitives for building, executing, and evaluating individual
  smoke probes. A probe is a single CLI invocation whose exit code and
  stdout are checked against optional expectations.

  This module is internal to the `Smoke` subsystem and should not be
  called directly by application code.
  """

  alias SymphonyElixir.Smoke.ResultStatus

  # ── Probe Construction ─────────────────────────────────────────────

  @doc """
  Builds a probe descriptor with an optional `expect_stdout` assertion.
  """
  @spec probe(String.t(), [String.t()]) :: map()
  def probe(id, argv), do: %{id: id, argv: argv, expect_stdout: nil}

  @spec probe(String.t(), [String.t()], keyword()) :: map()
  def probe(id, argv, opts) when is_list(opts),
    do: %{id: id, argv: argv, expect_stdout: Keyword.get(opts, :expect_stdout)}

  @doc """
  Creates a synthetic failure probe result without executing any command.
  """
  @spec synthetic_failure_probe(String.t(), String.t()) :: map()
  def synthetic_failure_probe(id, summary) do
    %{
      id: id,
      argv: [],
      ok: false,
      exit_code: 1,
      duration_ms: 0,
      stdout: "",
      stderr: "",
      summary: summary
    }
  end

  # ── Probe Execution ────────────────────────────────────────────────

  @doc """
  Executes a probe descriptor by invoking the CLI and comparing results.
  """
  @spec run_probe(map(), map(), map()) :: map()
  def run_probe(%{id: id, argv: argv, expect_stdout: expect_stdout}, cli_deps, deps) do
    started_at_ms = deps.monotonic_time_ms.()
    {stdout, stderr, exit_code} = deps.cli_evaluate.(argv, cli_deps)
    {ok, summary} = probe_status_and_summary(stdout, stderr, exit_code, expect_stdout)

    %{
      id: id,
      argv: argv,
      ok: ok,
      exit_code: exit_code,
      duration_ms: deps.monotonic_time_ms.() - started_at_ms,
      stdout: stdout,
      stderr: stderr,
      summary: summary
    }
  end

  @doc """
  Appends a probe execution result to an accumulator list.
  """
  @spec run_destructive_probe([map()], map(), map(), map()) :: [map()]
  def run_destructive_probe(acc, probe, cli_deps, deps) do
    acc ++ [run_probe(probe, cli_deps, deps)]
  end

  @doc """
  Executes a system-level step (e.g. git commands) and wraps the result
  as a probe result map.
  """
  @spec run_system_step(String.t(), map(), (-> map())) :: map()
  def run_system_step(id, deps, fun) when is_function(fun, 0) do
    started_at_ms = deps.monotonic_time_ms.()
    step = fun.()
    stdout = Map.get(step, :stdout, "")
    stderr = Map.get(step, :stderr, "")
    ok = Map.get(step, :ok, false)
    exit_code = Map.get(step, :exit_code, if(ok, do: 0, else: 1))
    summary = Map.get(step, :summary, summarize_output(stdout, stderr))

    %{
      id: id,
      argv: Map.get(step, :argv, []),
      ok: ok,
      exit_code: exit_code,
      duration_ms: deps.monotonic_time_ms.() - started_at_ms,
      stdout: stdout,
      stderr: stderr,
      summary: summary
    }
  end

  @doc """
  Builds a probe result map from raw values. Used by long-running poll
  loops that manage their own timing.
  """
  @spec probe_result(String.t(), [String.t()], integer(), map(), boolean(), non_neg_integer(), String.t(), String.t(), String.t()) :: map()
  def probe_result(id, argv, started_at_ms, deps, ok, exit_code, stdout, stderr, summary) do
    %{
      id: id,
      argv: argv,
      ok: ok,
      exit_code: exit_code,
      duration_ms: deps.monotonic_time_ms.() - started_at_ms,
      stdout: stdout,
      stderr: stderr,
      summary: summary
    }
  end

  # ── Output Helpers ─────────────────────────────────────────────────

  @doc """
  Extracts the first line from stderr (preferred) or stdout as a summary.
  """
  @spec summarize_output(String.t(), String.t()) :: String.t()
  def summarize_output(stdout, stderr) do
    candidate =
      if String.trim(stderr) != "" do
        stderr
      else
        stdout
      end

    candidate
    |> String.split("\n", trim: true)
    |> List.first()
    |> case do
      nil -> ""
      line -> truncate_summary(line)
    end
  end

  @doc """
  Returns an empty string for success exit codes, otherwise the output.
  """
  @spec failure_output(non_neg_integer(), String.t()) :: String.t()
  def failure_output(0, _output), do: ""
  def failure_output(_exit_code, output), do: output

  @doc """
  Returns `nil` for `nil` or empty strings, otherwise the value unchanged.
  """
  @spec blank_to_nil(term()) :: term()
  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  @spec status_label(boolean()) :: String.t()
  def status_label(true), do: ResultStatus.line_status(true)
  def status_label(false), do: ResultStatus.failed()

  @spec probe_status_label(boolean()) :: String.t()
  def probe_status_label(status), do: ResultStatus.upper_probe_status(status)

  # ── Private ────────────────────────────────────────────────────────

  defp probe_status_and_summary(stdout, stderr, exit_code, nil) do
    {exit_code == 0, summarize_output(stdout, stderr)}
  end

  defp probe_status_and_summary(stdout, stderr, exit_code, expected_stdout) do
    summary = summarize_output(stdout, stderr)

    cond do
      exit_code != 0 ->
        {false, summary}

      normalize_probe_output(stdout) == expected_stdout ->
        {true, summary}

      true ->
        {false, truncate_summary("Expected stdout #{inspect(expected_stdout)} but got #{inspect(normalize_probe_output(stdout))}")}
    end
  end

  defp normalize_probe_output(output) do
    output
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end

  defp truncate_summary(line) when byte_size(line) <= 160, do: line
  defp truncate_summary(line), do: binary_part(line, 0, 157) <> "..."
end
