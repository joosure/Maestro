defmodule SymphonyElixir.RepoProvider.GitHub.PullRequestHandler do
  @moduledoc """
  Pull request lifecycle operations for the GitHub adapter.

  Handles viewing, creation, editing, closing, merging, and check
  status retrieval through the `gh` CLI. Called by `GitHub.Adapter`
  for all PR-related callbacks.
  """

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub.CLI
  alias SymphonyElixir.RepoProvider.GitHub.Normalizer

  @type repo_config :: map()

  # ── PR View ──────────────────────────────────────────────────────

  @spec pr_view(repo_config(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pr_view(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts) do
      args =
        [
          "pr",
          "view",
          pr_target,
          "--repo",
          repository,
          "--json",
          "number,url,state,title,body,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus"
        ]

      case CLI.run_command("gh", args, opts) do
        {:ok, output} ->
          case Jason.decode(output) do
            {:ok, payload} when is_map(payload) ->
              {:ok, payload}

            {:ok, payload} ->
              {:error,
               Error.runtime_failure(
                 :github_invalid_payload,
                 "Unexpected GitHub PR payload",
                 payload
               )}

            {:error, reason} ->
              {:error,
               Error.runtime_failure(
                 :github_invalid_payload,
                 "Failed to decode GitHub PR payload",
                 reason
               )}
          end

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, pr_view_error(output)}
      end
    end
  end

  # ── PR Create ────────────────────────────────────────────────────

  @spec pr_create(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def pr_create(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts) do
      args =
        ["pr", "create", "--repo", repository]
        |> CLI.maybe_append_option("--title", opts[:title])
        |> CLI.maybe_append_option("--body", opts[:body])
        |> CLI.maybe_append_option("--base", opts[:base])
        |> CLI.maybe_append_option("--head", opts[:head])

      case CLI.run_command("gh", args, opts) do
        {:ok, output} ->
          {:ok, CLI.extract_scalar_output(output)}

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_create_failed, String.trim(output))}
      end
    end
  end

  # ── PR Edit ──────────────────────────────────────────────────────

  @spec pr_edit(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def pr_edit(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts),
         {:ok, args} <- pr_edit_args(repository, pr_target, opts),
         {:ok, url} <- resolve_pr_url(repository, pr_target, opts) do
      case CLI.run_command("gh", args, opts) do
        {:ok, _output} ->
          {:ok, url}

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_edit_failed, String.trim(output))}
      end
    end
  end

  # ── PR Add Label ────────────────────────────────────────────────

  @spec pr_add_label(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def pr_add_label(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, label} <- require_label(opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts),
         {:ok, url} <- resolve_pr_url(repository, pr_target, opts) do
      args = ["pr", "edit", pr_target, "--repo", repository, "--add-label", label]

      case CLI.run_command("gh", args, opts) do
        {:ok, _output} ->
          {:ok, url}

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_add_label_failed, String.trim(output))}
      end
    end
  end

  # ── PR Close ─────────────────────────────────────────────────────

  @spec pr_close(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def pr_close(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts),
         {:ok, url} <- resolve_pr_url(repository, pr_target, opts) do
      args = ["pr", "close", pr_target, "--repo", repository] |> CLI.maybe_append_option("--comment", opts[:comment])

      case CLI.run_command("gh", args, opts) do
        {:ok, _output} ->
          {:ok, url}

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_close_failed, String.trim(output))}
      end
    end
  end

  # ── PR Merge ─────────────────────────────────────────────────────

  @spec pr_merge(repo_config(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def pr_merge(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts),
         {:ok, url} <- resolve_pr_url(repository, pr_target, opts) do
      args =
        ["pr", "merge", pr_target, "--repo", repository]
        |> maybe_append_merge_style(opts[:merge_style] || "merge")
        |> CLI.maybe_append_option("--subject", opts[:subject])
        |> CLI.maybe_append_option("--body", opts[:body])

      case CLI.run_command("gh", args, opts) do
        {:ok, _output} ->
          {:ok, url}

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_merge_failed, String.trim(output))}
      end
    end
  end

  # ── PR Checks ────────────────────────────────────────────────────

  @spec pr_checks(repo_config(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def pr_checks(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts) do
      args =
        [
          "pr",
          "checks",
          pr_target,
          "--repo",
          repository,
          "--json",
          "bucket,completedAt,description,link,name,startedAt,state,workflow"
        ]

      read_check_runs(args, opts)
    end
  end

  # ── Close PRs for Branch ─────────────────────────────────────────

  @spec close_open_pull_requests_for_branch(repo_config(), String.t(), keyword()) ::
          :ok | {:error, Error.t()}
  def close_open_pull_requests_for_branch(repo, branch, opts) do
    if gh_available?(opts) and gh_authenticated?(opts) do
      case CLI.require_repository(repo, opts) do
        {:ok, repository} ->
          repository
          |> list_open_pull_request_numbers(branch, opts)
          |> Enum.each(&close_pull_request(repository, branch, &1, opts))

        {:error, %Error{} = error} ->
          {:error, error}
      end
    else
      :ok
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp maybe_append_merge_style(args, "squash"), do: args ++ ["--squash"]
  defp maybe_append_merge_style(args, "rebase"), do: args ++ ["--rebase"]
  defp maybe_append_merge_style(args, _style), do: args ++ ["--merge"]

  defp pr_edit_args(repository, pr_target, opts) do
    args =
      ["pr", "edit", pr_target, "--repo", repository]
      |> CLI.maybe_append_option("--title", opts[:title])
      |> CLI.maybe_append_option("--body", opts[:body])
      |> CLI.maybe_append_option("--base", opts[:base])

    if Enum.any?([opts[:title], opts[:body], opts[:base]], &present_binary?/1) do
      {:ok, args}
    else
      {:error, Error.invalid_invocation("GitHub pr-edit requires at least one editable field")}
    end
  end

  defp present_binary?(value) when is_binary(value), do: value != ""
  defp present_binary?(_value), do: false

  defp require_label(opts) do
    case opts[:label] do
      label when is_binary(label) and label != "" ->
        {:ok, label}

      _other ->
        {:error, Error.invalid_invocation("GitHub pr-add-label requires a non-empty label")}
    end
  end

  defp resolve_pr_url(repository, pr_target, opts) do
    args = ["pr", "view", pr_target, "--repo", repository, "--json", "url", "--jq", ".url"]

    case CLI.run_command("gh", args, opts) do
      {:ok, output} ->
        {:ok, CLI.extract_scalar_output(output)}

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        {:error, Error.runtime_failure(:github_pr_view_failed, String.trim(output))}
    end
  end

  defp gh_available?(opts), do: CLI.find_executable("gh", opts) != nil

  defp pr_view_error(output) do
    output = String.trim(output)

    if pr_not_found_output?(output) do
      Error.runtime_failure(
        :github_pr_not_found,
        "No GitHub pull request found for the requested target.",
        %{output: output}
      )
    else
      Error.runtime_failure(:github_pr_view_failed, output)
    end
  end

  defp pr_not_found_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "no pull requests found") or
      String.contains?(normalized, "could not resolve to a pullrequest")
  end

  defp gh_authenticated?(opts) do
    match?({:ok, _output}, CLI.run_command("gh", ["auth", "status"], opts))
  end

  defp read_check_runs(args, opts) do
    case CLI.run_command("gh", args, opts) do
      {:ok, output} ->
        decode_check_runs(output)

      {:error, {:enoent, _output}} ->
        {:error, CLI.enoent_error()}

      {:error, {_status, output}} ->
        if no_checks_reported_output?(output) do
          {:ok, []}
        else
          decode_or_check_status(output)
        end
    end
  end

  defp decode_or_check_status(output) do
    case decode_check_runs(output) do
      {:ok, checks} -> {:ok, checks}
      {:error, _reason} -> {:error, Error.runtime_failure(:github_cli_status, String.trim(output))}
    end
  end

  defp decode_check_runs(output) do
    case CLI.decode_json_output(output, :github_invalid_payload, "Failed to decode GitHub check payload") do
      {:ok, payload} when is_list(payload) ->
        {:ok, Enum.flat_map(payload, &Normalizer.normalize_check_run/1)}

      {:ok, payload} ->
        {:error,
         Error.runtime_failure(
           :github_invalid_payload,
           "Unexpected GitHub check payload",
           payload
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp no_checks_reported_output?(output) when is_binary(output) do
    output
    |> String.downcase()
    |> String.contains?("no checks reported")
  end

  defp list_open_pull_request_numbers(repo, branch, opts) do
    case CLI.run_command(
           "gh",
           [
             "pr",
             "list",
             "--repo",
             repo,
             "--head",
             branch,
             "--state",
             "open",
             "--json",
             "number",
             "--jq",
             ".[].number"
           ],
           opts
         ) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp close_pull_request(repo, branch, pr_number, opts) do
    info = Keyword.get(opts, :info, fn message -> Mix.shell().info(message) end)
    error = Keyword.get(opts, :error, fn message -> Mix.shell().error(message) end)

    case CLI.run_command(
           "gh",
           ["pr", "close", pr_number, "--repo", repo, "--comment", closing_comment(branch)],
           opts
         ) do
      {:ok, _output} ->
        info.("Closed PR ##{pr_number} for branch #{branch}")

      {:error, {status, output}} ->
        trimmed_output = String.trim(output)

        error.("Failed to close PR ##{pr_number} for branch #{branch}: exit #{status}#{format_output(trimmed_output)}")
    end
  end

  defp closing_comment(branch) do
    "Closing because the issue for branch #{branch} entered a terminal state without merge."
  end

  defp format_output(""), do: ""
  defp format_output(output), do: " output=#{inspect(output)}"
end
