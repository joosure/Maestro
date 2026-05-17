defmodule SymphonyElixir.RepoProvider.Smoke.ReadOnly do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [blank_to_nil: 1, probe: 2]

  alias SymphonyElixir.RepoProvider.CommandNames
  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Args

  @current_kind_command CommandNames.current_kind()
  @auth_status_command CommandNames.auth_status()
  @pr_view_command CommandNames.pr_view()
  @pr_reviews_command CommandNames.pr_reviews()
  @pr_checks_command CommandNames.pr_checks()
  @api_command CommandNames.api()

  @spec build_probes(keyword(), nil | String.t()) :: [map()]
  def build_probes(opts, provider_override) do
    pr_number = blank_to_nil(Keyword.get(opts, :pr))
    api_endpoint = blank_to_nil(Keyword.get(opts, :api_endpoint))
    api_jq = blank_to_nil(Keyword.get(opts, :api_jq))

    [
      probe(@current_kind_command, Args.provider_argv(provider_override, [@current_kind_command])),
      probe(@auth_status_command, Args.provider_argv(provider_override, [@auth_status_command]))
    ] ++
      pr_probes(pr_number, provider_override) ++
      api_probes(api_endpoint, api_jq, provider_override)
  end

  defp pr_probes(nil, _provider_override), do: []

  defp pr_probes(pr_number, provider_override) do
    [
      probe(
        @pr_view_command,
        Args.provider_argv(provider_override, [@pr_view_command, pr_number, "--json", "url", "-q", ".url"])
      ),
      probe(
        @pr_reviews_command,
        Args.provider_argv(provider_override, [@pr_reviews_command, pr_number, "--json", "state", "-q", ".[0].state"])
      ),
      probe(@pr_checks_command, Args.provider_argv(provider_override, [@pr_checks_command, pr_number]))
    ]
  end

  defp api_probes(nil, _api_jq, _provider_override), do: []

  defp api_probes(api_endpoint, api_jq, provider_override) do
    argv =
      [@api_command, api_endpoint]
      |> maybe_append_query(api_jq)

    [probe(@api_command, Args.provider_argv(provider_override, argv))]
  end

  defp maybe_append_query(argv, nil), do: argv
  defp maybe_append_query(argv, jq), do: argv ++ ["-q", jq]
end
