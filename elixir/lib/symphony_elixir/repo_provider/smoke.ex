defmodule SymphonyElixir.RepoProvider.Smoke do
  @moduledoc """
  Repo-provider smoke test orchestrator.

  Coordinates read-only, destructive, and CNB auto-provision smoke
  test modes. Delegates probe execution to `Smoke.ProbeRunner` and
  CNB-specific workflows to `Smoke.CNBProvisioner`.

  ## Public API

    * `run/2` - execute a smoke suite and return a report map
    * `format_text/1` - render a report as human-readable text
    * `to_map/1` - convert a report to a serializable map
  """

  alias SymphonyElixir.RepoProvider.RuntimeConfig
  alias SymphonyElixir.RepoProvider.Smoke.{CNBProvisioner, Destructive, Events, Mode, ReadOnly, Report, Runtime}
  alias SymphonyElixir.RepoProvider.Smoke.ProbeRunner

  @repo_provider_runtime "symphony"

  @type probe_result :: %{
          id: String.t(),
          argv: [String.t()],
          ok: boolean(),
          exit_code: non_neg_integer(),
          duration_ms: non_neg_integer(),
          stdout: String.t(),
          stderr: String.t(),
          summary: String.t()
        }

  @type report :: %{
          smoke_mode: String.t(),
          provider_kind: String.t(),
          repo_provider_runtime: String.t(),
          repository: String.t() | nil,
          ok: boolean(),
          duration_ms: non_neg_integer(),
          probe_count: non_neg_integer(),
          passed_count: non_neg_integer(),
          failed_count: non_neg_integer(),
          probes: [probe_result()]
        }

  @type deps :: %{
          required(:env) => (-> %{optional(String.t()) => String.t()} | [{String.t(), String.t()}]),
          required(:command_opts) => (-> keyword()),
          required(:cli_evaluate) => ([String.t()], map() -> {String.t(), String.t(), non_neg_integer()}),
          required(:monotonic_time_ms) => (-> integer()),
          required(:emit_event) => (atom(), atom(), map() -> map()),
          optional(:system_cmd) => (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()}),
          optional(:mk_temp_dir) => (String.t() -> {:ok, String.t()} | {:error, term()}),
          optional(:write_file) => (String.t(), iodata() -> :ok | {:error, term()}),
          optional(:rm_rf) => (String.t() -> any()),
          optional(:sleep_ms) => (non_neg_integer() -> any())
        }

  @spec run(keyword(), deps()) :: report()
  def run(opts, deps \\ Runtime.runtime_deps()) when is_list(opts) and is_map(deps) do
    env_map = Runtime.env_map(opts, deps)
    repo_config = RuntimeConfig.from_env(env_map)
    provider_override = ProbeRunner.blank_to_nil(Keyword.get(opts, :provider))
    provider_kind = provider_override || RuntimeConfig.current_kind(repo_config)
    repository = Map.get(env_map, "SYMPHONY_REPO_PROVIDER_REPOSITORY")
    smoke_mode = Mode.smoke_mode(opts)
    started_at_ms = deps.monotonic_time_ms.()

    Events.emit_started(
      deps,
      provider_kind,
      @repo_provider_runtime,
      repository,
      smoke_mode,
      Mode.planned_probe_count(opts, provider_override, repo_config)
    )

    cli_deps = Runtime.cli_deps(env_map, deps)
    probe_results = run_probes(smoke_mode, opts, provider_override, repo_config, env_map, cli_deps, deps)
    duration_ms = deps.monotonic_time_ms.() - started_at_ms

    report =
      Report.build(
        smoke_mode,
        provider_kind,
        @repo_provider_runtime,
        repository,
        probe_results,
        duration_ms
      )

    Events.emit_finished(deps, report)
    report
  end

  @spec format_text(report()) :: String.t()
  defdelegate format_text(report), to: Report

  @spec to_map(report()) :: map()
  defdelegate to_map(report), to: Report

  defp run_probes("destructive", opts, provider_override, _repo_config, _env_map, cli_deps, deps) do
    Destructive.run(opts, provider_override, cli_deps, deps)
  end

  defp run_probes("destructive_auto_provision_cnb_pipeline", opts, provider_override, repo_config, env_map, cli_deps, deps) do
    CNBProvisioner.run(opts, provider_override, repo_config, env_map, cli_deps, deps)
  end

  defp run_probes(_smoke_mode, opts, provider_override, _repo_config, _env_map, cli_deps, deps) do
    opts
    |> ReadOnly.build_probes(provider_override)
    |> Enum.map(&ProbeRunner.run_probe(&1, cli_deps, deps))
  end
end
