defmodule SymphonyElixir.RepoProvider.Smoke.Events do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner, only: [status_label: 1]

  @spec emit_started(map(), String.t(), String.t(), String.t() | nil, String.t(), non_neg_integer()) :: map()
  def emit_started(deps, provider_kind, backend, repository, smoke_mode, probe_count) do
    deps.emit_event.(:info, :repo_provider_smoke_started, %{
      component: "repo_provider.smoke",
      provider_kind: provider_kind,
      repo_provider_runtime: backend,
      smoke_mode: smoke_mode,
      repository: repository,
      probe_count: probe_count,
      payload_summary: "provider=#{provider_kind} runtime=#{backend} mode=#{smoke_mode} probes=#{probe_count}"
    })
  end

  @spec emit_finished(map(), map()) :: map()
  def emit_finished(deps, report) do
    level = if report.ok, do: :info, else: :warning
    first_failure = Enum.find(report.probes, &(not &1.ok))

    deps.emit_event.(level, :repo_provider_smoke_finished, %{
      component: "repo_provider.smoke",
      provider_kind: report.provider_kind,
      repo_provider_runtime: report.repo_provider_runtime,
      smoke_mode: report.smoke_mode,
      repository: report.repository,
      status: status_label(report.ok),
      duration_ms: report.duration_ms,
      probe_count: report.probe_count,
      passed_count: report.passed_count,
      failed_count: report.failed_count,
      exit_code: if(report.ok, do: 0, else: 1),
      error: if(first_failure, do: "#{first_failure.id}: #{first_failure.summary}", else: nil),
      result_summary:
        "provider=#{report.provider_kind} runtime=#{report.repo_provider_runtime} mode=#{report.smoke_mode} status=#{status_label(report.ok)} probes=#{report.probe_count} passed=#{report.passed_count} failed=#{report.failed_count}"
    })
  end
end
