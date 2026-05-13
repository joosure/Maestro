defmodule SymphonyElixir.RepoProvider.Smoke.ReadOnly do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [blank_to_nil: 1, probe: 2]

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Args

  @spec build_probes(keyword(), nil | String.t()) :: [map()]
  def build_probes(opts, provider_override) do
    pr_number = blank_to_nil(Keyword.get(opts, :pr))
    api_endpoint = blank_to_nil(Keyword.get(opts, :api_endpoint))
    api_jq = blank_to_nil(Keyword.get(opts, :api_jq))

    [
      probe("current-kind", Args.provider_argv(provider_override, ["current-kind"])),
      probe("auth-status", Args.provider_argv(provider_override, ["auth-status"]))
    ] ++
      pr_probes(pr_number, provider_override) ++
      api_probes(api_endpoint, api_jq, provider_override)
  end

  defp pr_probes(nil, _provider_override), do: []

  defp pr_probes(pr_number, provider_override) do
    [
      probe(
        "pr-view",
        Args.provider_argv(provider_override, ["pr-view", pr_number, "--json", "url", "-q", ".url"])
      ),
      probe(
        "pr-reviews",
        Args.provider_argv(provider_override, ["pr-reviews", pr_number, "--json", "state", "-q", ".[0].state"])
      ),
      probe("pr-checks", Args.provider_argv(provider_override, ["pr-checks", pr_number]))
    ]
  end

  defp api_probes(nil, _api_jq, _provider_override), do: []

  defp api_probes(api_endpoint, api_jq, provider_override) do
    argv =
      ["api", api_endpoint]
      |> maybe_append_query(api_jq)

    [probe("api", Args.provider_argv(provider_override, argv))]
  end

  defp maybe_append_query(argv, nil), do: argv
  defp maybe_append_query(argv, jq), do: argv ++ ["-q", jq]
end
