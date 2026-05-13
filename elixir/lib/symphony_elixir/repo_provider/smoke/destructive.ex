defmodule SymphonyElixir.RepoProvider.Smoke.Destructive do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [blank_to_nil: 1, probe: 2, probe: 3, run_destructive_probe: 4, run_probe: 3, synthetic_failure_probe: 2]

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Args

  @spec run(keyword(), nil | String.t(), map(), map()) :: [map()]
  def run(opts, provider_override, cli_deps, deps) do
    preflight_results =
      [
        probe("current-kind", Args.provider_argv(provider_override, ["current-kind"])),
        probe("auth-status", Args.provider_argv(provider_override, ["auth-status"]))
      ]
      |> Enum.map(&run_probe(&1, cli_deps, deps))

    if Enum.any?(preflight_results, &(not &1.ok)) do
      preflight_results
    else
      destructive_results(opts, provider_override, cli_deps, deps, preflight_results)
    end
  end

  defp destructive_results(opts, provider_override, cli_deps, deps, acc) do
    head = Keyword.fetch!(opts, :head)
    base = blank_to_nil(Keyword.get(opts, :base))
    title = destructive_title(opts, head, base)
    create_body = destructive_body(opts, head, base)
    edited_body = Args.destructive_edited_body(create_body)

    create_probe =
      probe(
        "pr-create",
        Args.provider_argv(
          provider_override,
          Args.destructive_create_argv(title, create_body, base, head)
        )
      )

    create_result = run_probe(create_probe, cli_deps, deps)
    acc = acc ++ [create_result]

    case Args.created_pull(create_result) do
      {:ok, pr_url, pr_number} ->
        acc
        |> run_destructive_probe(
          probe(
            "pr-view-created",
            Args.provider_argv(provider_override, ["pr-view", pr_number, "--json", "url", "-q", ".url"]),
            expect_stdout: pr_url
          ),
          cli_deps,
          deps
        )
        |> run_destructive_probe(
          probe(
            "pr-edit",
            Args.provider_argv(provider_override, ["pr-edit", pr_number, "--body", edited_body])
          ),
          cli_deps,
          deps
        )
        |> run_destructive_probe(
          probe(
            "pr-view-edited",
            Args.provider_argv(provider_override, ["pr-view", pr_number, "--json", "body", "-q", ".body"]),
            expect_stdout: edited_body
          ),
          cli_deps,
          deps
        )
        |> run_close_sequence(provider_override, pr_number, cli_deps, deps)

      {:error, message} ->
        acc ++ [synthetic_failure_probe("pr-create-resolve", message)]
    end
  end

  defp run_close_sequence(acc, provider_override, pr_number, cli_deps, deps) do
    close_result =
      run_probe(
        probe("pr-close", Args.provider_argv(provider_override, ["pr-close", pr_number])),
        cli_deps,
        deps
      )

    acc = acc ++ [close_result]

    if close_result.ok do
      acc ++
        [
          run_probe(
            probe(
              "pr-view-closed",
              Args.provider_argv(provider_override, ["pr-view", pr_number, "--json", "state", "-q", ".state"]),
              expect_stdout: "CLOSED"
            ),
            cli_deps,
            deps
          )
        ]
    else
      acc
    end
  end

  defp destructive_title(opts, head, base) do
    Keyword.get(opts, :title) || "Repo-provider destructive smoke for #{head} -> #{base || "default"}"
  end

  defp destructive_body(opts, head, base) do
    Keyword.get(opts, :body) ||
      "Created by Symphony repo-provider destructive smoke.\n\nHead: #{head}\nBase: #{base || "default"}"
  end
end
