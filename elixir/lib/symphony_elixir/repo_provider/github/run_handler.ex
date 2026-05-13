defmodule SymphonyElixir.RepoProvider.GitHub.RunHandler do
  @moduledoc """
  CI run operations for the GitHub adapter.

  Handles listing, viewing, and log rendering of GitHub Actions
  workflow runs through the `gh` CLI. Called by `GitHub.Adapter`
  for all run-related callbacks.
  """

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub.CLI
  alias SymphonyElixir.RepoProvider.GitHub.Normalizer

  @type repo_config :: map()

  # ── Run List ─────────────────────────────────────────────────────

  @spec run_list(repo_config(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def run_list(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts) do
      args =
        ["run", "list", "--repo", repository, "--json", run_list_fields()]
        |> CLI.maybe_append_option("--branch", opts[:branch])
        |> CLI.maybe_append_integer_option("--limit", opts[:limit])

      case CLI.run_command("gh", args, opts) do
        {:ok, output} ->
          with {:ok, payload} <-
                 CLI.decode_json_output(
                   output,
                   :github_invalid_payload,
                   "Failed to decode GitHub run-list payload"
                 ),
               {:ok, runs} <-
                 CLI.expect_list(payload, :github_invalid_payload, "Unexpected GitHub run-list payload") do
            {:ok, Enum.map(runs, &Normalizer.normalize_run_summary/1)}
          end

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_run_list_failed, String.trim(output))}
      end
    end
  end

  # ── Run View ─────────────────────────────────────────────────────

  @spec run_view(repo_config(), keyword()) :: {:ok, map() | String.t()} | {:error, Error.t()}
  def run_view(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, run_id} <- require_run_id(opts[:run_id]) do
      if opts[:log?] do
        with {:ok, run} <- fetch_run_details(repository, run_id, opts),
             {:ok, raw_log} <- fetch_run_log(repository, run_id, opts) do
          {:ok, Normalizer.render_run_log(run, raw_log)}
        end
      else
        fetch_run_details(repository, run_id, opts)
      end
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp require_run_id(run_id) when is_binary(run_id) and run_id != "", do: {:ok, run_id}

  defp require_run_id(_run_id) do
    {:error, Error.runtime_failure(:github_run_id_required, "GitHub run-view requires a run id")}
  end

  defp fetch_run_details(repository, run_id, opts) do
    args = ["run", "view", run_id, "--repo", repository, "--json", run_view_fields()]

    case CLI.run_command("gh", args, opts) do
      {:ok, output} ->
        with {:ok, payload} <-
               CLI.decode_json_output(
                 output,
                 :github_invalid_payload,
                 "Failed to decode GitHub run-view payload"
               ),
             {:ok, run} <-
               CLI.expect_map(payload, :github_invalid_payload, "Unexpected GitHub run-view payload") do
          {:ok, Normalizer.normalize_run_detail(run)}
        end

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        {:error, Error.runtime_failure(:github_run_view_failed, String.trim(output))}
    end
  end

  defp fetch_run_log(repository, run_id, opts) do
    args = ["run", "view", run_id, "--repo", repository, "--log"]

    case CLI.run_command("gh", args, opts) do
      {:ok, output} ->
        {:ok, output}

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        {:error, Error.runtime_failure(:github_run_view_failed, String.trim(output))}
    end
  end

  defp run_list_fields do
    "attempt,conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,number,status,updatedAt,url,workflowName"
  end

  defp run_view_fields do
    "attempt,conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,number,startedAt,status,updatedAt,url,workflowName"
  end
end
