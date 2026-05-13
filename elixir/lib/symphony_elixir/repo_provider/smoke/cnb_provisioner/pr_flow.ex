defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.PRFlow do
  @moduledoc false

  import SymphonyElixir.RepoProvider.Smoke.ProbeRunner,
    only: [probe: 2, probe: 3, run_probe: 3, run_destructive_probe: 4, synthetic_failure_probe: 2]

  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.{Args, Git, Runs}

  @spec run_pr_flow(map(), nil | String.t(), map(), map(), [map()]) :: [map()]
  def run_pr_flow(context, provider_override, cli_deps, deps, acc) do
    create_result = create_pr(context, provider_override, cli_deps, deps)
    acc = acc ++ [create_result]

    case Args.created_pull(create_result) do
      {:ok, pr_url, pr_number} ->
        context
        |> Map.merge(%{
          pr_url: pr_url,
          pr_number: pr_number,
          edited_body: Args.destructive_edited_body(context.body)
        })
        |> run_pr_verification(provider_override, cli_deps, deps, acc)

      {:error, message} ->
        cleanup(
          acc ++ [synthetic_failure_probe("pr-create-resolve", message)],
          provider_override,
          context,
          cli_deps,
          deps
        )
    end
  end

  defp create_pr(context, provider_override, cli_deps, deps) do
    run_probe(
      probe(
        "pr-create",
        Args.provider_argv(
          provider_override,
          Args.destructive_create_argv(context.title, context.body, context.base, context.head)
        )
      ),
      cli_deps,
      deps
    )
  end

  defp run_pr_verification(context, provider_override, cli_deps, deps, acc) do
    acc =
      acc
      |> run_destructive_probe(
        probe(
          "pr-view-created",
          Args.provider_argv(provider_override, ["pr-view", context.pr_number, "--json", "url", "-q", ".url"]),
          expect_stdout: context.pr_url
        ),
        cli_deps,
        deps
      )
      |> run_destructive_probe(
        probe(
          "pr-edit",
          Args.provider_argv(provider_override, ["pr-edit", context.pr_number, "--body", context.edited_body])
        ),
        cli_deps,
        deps
      )
      |> run_destructive_probe(
        probe(
          "pr-view-edited",
          Args.provider_argv(provider_override, ["pr-view", context.pr_number, "--json", "body", "-q", ".body"]),
          expect_stdout: context.edited_body
        ),
        cli_deps,
        deps
      )

    {run_list_result, run_id} = Runs.wait_for_runs(provider_override, context, cli_deps, deps)
    acc = acc ++ [run_list_result]

    acc =
      case run_id do
        run_id when is_binary(run_id) ->
          acc ++ [Runs.run_view_log(provider_override, run_id, cli_deps, deps)]

        _other ->
          acc
      end

    cleanup(acc, provider_override, context, cli_deps, deps)
  end

  defp cleanup(acc, provider_override, context, cli_deps, deps) do
    acc =
      if is_binary(context.pr_number) do
        acc
        |> run_destructive_probe(
          probe("pr-close", Args.provider_argv(provider_override, ["pr-close", context.pr_number])),
          cli_deps,
          deps
        )
        |> maybe_verify_closed_pr(provider_override, context.pr_number, cli_deps, deps)
      else
        acc
      end

    acc ++ [Git.delete_branch(context, deps)]
  end

  defp maybe_verify_closed_pr(acc, provider_override, pr_number, cli_deps, deps) do
    case List.last(acc) do
      %{id: "pr-close", ok: true} ->
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

      _other ->
        acc
    end
  end
end
