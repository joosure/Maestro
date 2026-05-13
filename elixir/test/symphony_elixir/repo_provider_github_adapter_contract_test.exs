defmodule SymphonyElixir.RepoProviderGitHubAdapterContractTest do
  use ExUnit.Case, async: false

  def missing_gh_runner(_command, _args), do: {:error, {:enoent, ""}}
  def missing_gh_executable(_command), do: nil

  use SymphonyElixir.RepoProviderAdapterContract,
    adapter: SymphonyElixir.RepoProvider.GitHub.Adapter,
    config: %{
      provider: %{
        kind: "github",
        repository: "acme/widgets",
        options: %{required_pr_label: "release-ready"}
      }
    },
    callback_opts: %{
      auth_status: [command_runner: &__MODULE__.missing_gh_runner/2],
      pr_view: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      pr_create: [
        title: "Contract PR",
        body: "Contract body",
        head: "feature/contract",
        base: "main",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_edit: [
        number: "1",
        title: "Updated contract PR",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_add_label: [
        number: "1",
        label: "release-ready",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_issue_comments: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      pr_add_issue_comment: [
        number: "1",
        body: "[codex] contract note",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_reviews: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      pr_submit_review: [
        number: "1",
        event: "comment",
        body: "[codex] review note",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_review_comments: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      pr_reply_review_comment: [
        number: "1",
        comment_id: "101",
        body: "[codex] acknowledged",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_close: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      pr_merge: [
        number: "1",
        merge_style: "merge",
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      pr_checks: [number: "1", command_runner: &__MODULE__.missing_gh_runner/2],
      api: [
        endpoint: "repos/{owner}/{repo}",
        method: "GET",
        fields: %{},
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      run_list: [branch: "main", limit: 1, command_runner: &__MODULE__.missing_gh_runner/2],
      run_view: [run_id: "100", command_runner: &__MODULE__.missing_gh_runner/2],
      close_open_pull_requests_for_branch: [
        executable_finder: &__MODULE__.missing_gh_executable/1,
        command_runner: &__MODULE__.missing_gh_runner/2
      ],
      healthcheck: [command_runner: &__MODULE__.missing_gh_runner/2]
    }
end
