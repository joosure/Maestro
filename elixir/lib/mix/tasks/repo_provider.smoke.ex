defmodule Mix.Tasks.RepoProvider.Smoke do
  use Mix.Task

  alias SymphonyElixir.CLI.RepoProviderSmoke, as: RepoProviderSmokeCLI

  @shortdoc "Run repo-provider smoke probes"

  @moduledoc """
  Runs smoke validation against the `symphony repo-provider` contract.

  By default this task probes:

    - `current-kind`
    - `auth-status`

  Optional probes:

    - `--pr <number>` adds `pr-view`, `pr-reviews`, and `pr-checks` for the given PR
    - `--api-endpoint <path>` adds a read-only CNB `api` GET probe
    - `--destructive --head <branch>` opts into a write-path smoke that
      creates, edits, verifies, and closes a PR
    - `--destructive --auto-provision-cnb-pipeline` is CNB-only and creates a
      temporary branch with a minimal `.cnb.yml`, validates `run-list` and
      `run-view --log`, then closes the PR and deletes the branch

  Usage:

      mix repo_provider.smoke [--provider <kind>] [--repo <slug>] [--pr <number>] [--api-endpoint <path>] [--api-jq <expr>] [--json]
      mix repo_provider.smoke [--provider <kind>] [--repo <slug>] --destructive --head <branch> [--base <branch>] [--title <text>] [--body <text>] [--json]
      mix repo_provider.smoke [--provider cnb] [--repo <slug>] --destructive --auto-provision-cnb-pipeline [--base <branch>] [--title <text>] [--body <text>] [--json]
  """
  @impl Mix.Task
  def run(args) do
    if Enum.any?(args, &(&1 in ["--help", "-h"])) do
      Mix.shell().info(@moduledoc)
    else
      {stdout, stderr, exit_code} = RepoProviderSmokeCLI.evaluate(args)

      if stdout != "", do: IO.write(stdout)

      case exit_code do
        0 ->
          :ok

        _other ->
          message =
            stderr
            |> String.trim()
            |> case do
              "" -> "repo_provider.smoke failed"
              value -> value
            end

          Mix.raise(message)
      end
    end
  end
end
