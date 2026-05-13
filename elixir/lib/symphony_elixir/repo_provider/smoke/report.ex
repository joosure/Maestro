defmodule SymphonyElixir.RepoProvider.Smoke.Report do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [probe_status_label: 1, status_label: 1]

  @spec build(String.t(), String.t(), String.t(), String.t() | nil, [map()], non_neg_integer()) :: map()
  def build(smoke_mode, provider_kind, repo_provider_runtime, repository, probe_results, duration_ms) do
    passed_count = Enum.count(probe_results, & &1.ok)
    failed_count = length(probe_results) - passed_count

    %{
      smoke_mode: smoke_mode,
      provider_kind: provider_kind,
      repo_provider_runtime: repo_provider_runtime,
      repository: repository,
      ok: failed_count == 0,
      duration_ms: duration_ms,
      probe_count: length(probe_results),
      passed_count: passed_count,
      failed_count: failed_count,
      probes: probe_results
    }
  end

  @spec format_text(map()) :: String.t()
  def format_text(report) when is_map(report) do
    header =
      "repo-provider smoke #{status_label(report.ok)} provider=#{report.provider_kind}" <>
        repository_segment(report.repository) <>
        " runtime=#{report.repo_provider_runtime}" <>
        " mode=#{report.smoke_mode}" <>
        " probes=#{report.probe_count}" <>
        " passed=#{report.passed_count}" <>
        " failed=#{report.failed_count}" <>
        " duration_ms=#{report.duration_ms}"

    lines =
      Enum.map(report.probes, fn probe ->
        "#{probe_status_label(probe.ok)} #{probe.id}" <>
          " exit=#{probe.exit_code}" <>
          " duration_ms=#{probe.duration_ms}" <>
          " summary=#{inspect(probe.summary)}"
      end)

    IO.iodata_to_binary([header, "\n", Enum.intersperse(lines, "\n"), "\n"])
  end

  @spec to_map(map()) :: map()
  def to_map(report) when is_map(report) do
    Map.update!(report, :probes, fn probes ->
      Enum.map(probes, fn probe ->
        probe
        |> Map.drop([:stdout, :stderr])
        |> Map.put(:stdout_bytes, byte_size(probe.stdout))
        |> Map.put(:stderr_bytes, byte_size(probe.stderr))
      end)
    end)
  end

  defp repository_segment(nil), do: ""
  defp repository_segment(""), do: ""
  defp repository_segment(repository), do: " repo=#{repository}"
end
