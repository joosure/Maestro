defmodule SymphonyElixir.GitHubChangeProposalLiveTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Platform.CommandEnv

  @moduletag :github_change_proposal_live
  @moduletag timeout: 600_000

  @run_env "SYMPHONY_RUN_GITHUB_CHANGE_PROPOSAL_LIVE"
  @review_checks_run_env "SYMPHONY_RUN_GITHUB_REVIEW_CHECKS_LIVE"
  @independent_approval_run_env "SYMPHONY_RUN_GITHUB_INDEPENDENT_APPROVAL_LIVE"
  @default_repository "acme/widgets"
  @default_base_branch "master"
  @default_branch_prefix "symphony/live"
  @default_checks_timeout_ms 900_000
  @default_checks_poll_ms 10_000

  @live_skip_reason if(System.get_env(@run_env) != "1",
                      do: "set #{@run_env}=1 to enable the real GitHub change-proposal live smoke"
                    )

  @review_checks_skip_reason if(System.get_env(@review_checks_run_env) != "1",
                               do: "set #{@review_checks_run_env}=1 to enable the real GitHub review/check live smoke"
                             )

  @independent_approval_skip_reason if(System.get_env(@independent_approval_run_env) != "1",
                                      do: "set #{@independent_approval_run_env}=1 to enable the real GitHub independent approval live smoke"
                                    )

  @tag skip: @live_skip_reason
  test "creates and snapshots a GitHub change proposal through typed repo tools" do
    repository = live_env("SOURCE_REPO_PROVIDER_REPOSITORY", @default_repository)
    remote_url = live_env("SOURCE_REPO_URL", "https://github.com/#{repository}.git")
    base_branch = live_env("SOURCE_REPO_BASE_BRANCH", @default_base_branch)
    branch_prefix = live_env("SOURCE_REPO_BRANCH_WORK_PREFIX", @default_branch_prefix)
    branch = live_branch(branch_prefix)
    root = tmp_dir!("github-change-proposal-live")
    repo_path = Path.join(root, "repo")

    try do
      clone_repo!(remote_url, base_branch, repo_path)
      configure_git_identity!(repo_path)

      context = dynamic_tool_context(repo_path, remote_url, repository, base_branch, branch_prefix)

      checkout =
        execute_success!(
          context,
          "repo_checkout",
          %{"branch" => branch, "base" => "origin/#{base_branch}", "mode" => "create"}
        )

      assert get_in(checkout, ["data", "branch"]) == branch
      assert get_in(checkout, ["data", "status", "clean"]) == true

      write_probe_file!(repo_path, repository, branch)

      commit =
        execute_success!(
          context,
          "repo_commit",
          %{"message" => "chore: add GitHub change-proposal live probe", "mode" => "all"}
        )

      head_sha = get_in(commit, ["data", "headSha"])
      assert is_binary(head_sha)

      push =
        execute_success!(
          context,
          "repo_push",
          %{"branch" => branch, "set_upstream" => true, "verify" => true}
        )

      assert get_in(push, ["data", "publishedHeadSha"]) == head_sha

      created =
        execute_success!(
          context,
          "repo_create_or_update_change_proposal",
          %{
            "mode" => "create",
            "title" => "Symphony GitHub typed live probe",
            "body" => live_pr_body(repository, branch),
            "base" => base_branch,
            "head" => branch
          }
        )

      change_proposal = get_in(created, ["data", "changeProposal"])
      assert is_map(change_proposal)
      assert change_proposal["url"] =~ "github.com/#{repository}/pull/"

      snapshot_target = change_proposal["number"] || change_proposal["url"] || branch

      snapshot =
        execute_success!(
          context,
          "repo_change_proposal_snapshot",
          %{"number" => snapshot_target, "include_discussion" => false, "include_checks" => false}
        )

      assert get_in(snapshot, ["data", "exists"]) == true
      assert get_in(snapshot, ["data", "changeProposal", "headRefName"]) == branch
      assert get_in(snapshot, ["data", "changeProposal", "baseRefName"]) == base_branch

      close_target = get_in(snapshot, ["data", "changeProposal", "number"]) || snapshot_target

      execute_success!(
        context,
        "repo_close_change_proposal",
        %{
          "number" => close_target,
          "comment" => "Closing temporary Symphony GitHub typed live probe."
        }
      )

      IO.puts(
        "github_change_proposal_live_probe " <>
          "repository=#{repository} branch=#{branch} head_sha=#{head_sha} " <>
          "change_proposal=#{change_proposal["url"]}"
      )
    after
      close_open_prs_for_branch(repository, branch)
      delete_remote_branch(repo_path, branch)
      File.rm_rf(root)
    end
  end

  @tag skip: @review_checks_skip_reason
  test "reads discussion and passing checks for a GitHub change proposal through typed repo tools" do
    repository = live_env("SOURCE_REPO_PROVIDER_REPOSITORY", @default_repository)
    remote_url = live_env("SOURCE_REPO_URL", "https://github.com/#{repository}.git")
    base_branch = live_env("SOURCE_REPO_BASE_BRANCH", @default_base_branch)
    branch_prefix = live_env("SOURCE_REPO_BRANCH_WORK_PREFIX", @default_branch_prefix)
    branch = live_branch(branch_prefix, "github-review-checks")
    root = tmp_dir!("github-review-checks-live")
    repo_path = Path.join(root, "repo")

    try do
      clone_repo!(remote_url, base_branch, repo_path)
      configure_git_identity!(repo_path)

      context = dynamic_tool_context(repo_path, remote_url, repository, base_branch, branch_prefix)

      checkout =
        execute_success!(
          context,
          "repo_checkout",
          %{"branch" => branch, "base" => "origin/#{base_branch}", "mode" => "create"}
        )

      assert get_in(checkout, ["data", "branch"]) == branch
      assert get_in(checkout, ["data", "status", "clean"]) == true

      write_probe_file!(repo_path, repository, branch)

      commit =
        execute_success!(
          context,
          "repo_commit",
          %{"message" => "chore: add GitHub review checks live probe", "mode" => "all"}
        )

      head_sha = get_in(commit, ["data", "headSha"])
      assert is_binary(head_sha)

      push =
        execute_success!(
          context,
          "repo_push",
          %{"branch" => branch, "set_upstream" => true, "verify" => true}
        )

      assert get_in(push, ["data", "publishedHeadSha"]) == head_sha

      created =
        execute_success!(
          context,
          "repo_create_or_update_change_proposal",
          %{
            "mode" => "create",
            "title" => "Symphony GitHub review/check live probe",
            "body" => live_review_checks_pr_body(repository, branch),
            "base" => base_branch,
            "head" => branch
          }
        )

      change_proposal = get_in(created, ["data", "changeProposal"])
      assert is_map(change_proposal)
      assert change_proposal["url"] =~ "github.com/#{repository}/pull/"

      target = change_proposal["number"] || change_proposal["url"] || branch

      publish_success_status_check(repository, head_sha)
      trigger_check_workflows(repository, branch)

      comment_body = "Symphony review/check live top-level comment for #{branch}."

      comment =
        execute_success!(
          context,
          "repo_add_change_proposal_comment",
          %{"number" => target, "body" => comment_body}
        )

      assert get_in(comment, ["data", "action"]) == "comment_added"

      review_body = "Symphony review/check live comment review for #{branch}."

      review =
        execute_success!(
          context,
          "repo_submit_change_proposal_review",
          %{"number" => target, "event" => "comment", "body" => review_body}
        )

      assert get_in(review, ["data", "action"]) == "review_submitted"

      snapshot =
        execute_success!(
          context,
          "repo_change_proposal_snapshot",
          %{"number" => target, "include_discussion" => false, "include_checks" => false}
        )

      assert get_in(snapshot, ["data", "exists"]) == true
      assert get_in(snapshot, ["data", "changeProposal", "headRefName"]) == branch
      assert get_in(snapshot, ["data", "changeProposal", "baseRefName"]) == base_branch

      discussion =
        execute_success!(
          context,
          "repo_read_change_proposal_discussion",
          %{
            "number" => target,
            "include_issue_comments" => true,
            "include_reviews" => true,
            "include_review_comments" => true
          }
        )

      discussion_summary = get_in(discussion, ["data", "discussion", "summary"])
      assert is_map(discussion_summary)
      assert discussion_summary["issueCommentCount"] >= 1
      assert discussion_summary["reviewCount"] >= 1
      assert get_in(discussion_summary, ["reviewStateCounts", "commented"]) >= 1

      checks = wait_for_passing_checks!(context, target)
      runs = get_in(checks, ["data", "checks", "runs"])
      assert is_list(runs)
      assert runs != []
      assert Enum.any?(runs, &(Map.get(&1, "name") == status_check_context()))

      close_target = get_in(snapshot, ["data", "changeProposal", "number"]) || target

      execute_success!(
        context,
        "repo_close_change_proposal",
        %{
          "number" => close_target,
          "comment" => "Closing temporary Symphony GitHub review/check live probe."
        }
      )

      IO.puts(
        "github_review_checks_live_probe " <>
          "repository=#{repository} branch=#{branch} head_sha=#{head_sha} " <>
          "change_proposal=#{change_proposal["url"]} checks=#{inspect(check_run_summary(runs))}"
      )
    after
      close_open_prs_for_branch(repository, branch)
      delete_remote_branch(repo_path, branch)
      File.rm_rf(root)
    end
  end

  @tag skip: @independent_approval_skip_reason
  test "reads independent approval for a GitHub change proposal through typed repo tools" do
    reviewer_token = required_live_env!("SYMPHONY_GITHUB_REVIEWER_TOKEN")
    repository = live_env("SOURCE_REPO_PROVIDER_REPOSITORY", @default_repository)
    remote_url = live_env("SOURCE_REPO_URL", "https://github.com/#{repository}.git")
    base_branch = live_env("SOURCE_REPO_BASE_BRANCH", @default_base_branch)
    branch_prefix = live_env("SOURCE_REPO_BRANCH_WORK_PREFIX", @default_branch_prefix)
    branch = live_branch(branch_prefix, "github-independent-approval")
    root = tmp_dir!("github-independent-approval-live")
    repo_path = Path.join(root, "repo")

    try do
      author_login = gh_login!()
      reviewer_login = gh_login!(reviewer_token)
      assert reviewer_login != author_login

      clone_repo!(remote_url, base_branch, repo_path)
      configure_git_identity!(repo_path)

      context = dynamic_tool_context(repo_path, remote_url, repository, base_branch, branch_prefix)

      checkout =
        execute_success!(
          context,
          "repo_checkout",
          %{"branch" => branch, "base" => "origin/#{base_branch}", "mode" => "create"}
        )

      assert get_in(checkout, ["data", "branch"]) == branch
      assert get_in(checkout, ["data", "status", "clean"]) == true

      write_probe_file!(repo_path, repository, branch)

      commit =
        execute_success!(
          context,
          "repo_commit",
          %{"message" => "chore: add GitHub independent approval live probe", "mode" => "all"}
        )

      head_sha = get_in(commit, ["data", "headSha"])
      assert is_binary(head_sha)

      push =
        execute_success!(
          context,
          "repo_push",
          %{"branch" => branch, "set_upstream" => true, "verify" => true}
        )

      assert get_in(push, ["data", "publishedHeadSha"]) == head_sha

      created =
        execute_success!(
          context,
          "repo_create_or_update_change_proposal",
          %{
            "mode" => "create",
            "title" => "Symphony GitHub independent approval live probe",
            "body" => live_independent_approval_pr_body(repository, branch, reviewer_login),
            "base" => base_branch,
            "head" => branch
          }
        )

      change_proposal = get_in(created, ["data", "changeProposal"])
      assert is_map(change_proposal)
      assert change_proposal["url"] =~ "github.com/#{repository}/pull/"

      target = change_proposal["number"] || change_proposal["url"] || branch

      submit_independent_approval!(reviewer_token, repository, target, branch)

      discussion =
        execute_success!(
          context,
          "repo_read_change_proposal_discussion",
          %{
            "number" => target,
            "include_issue_comments" => true,
            "include_reviews" => true,
            "include_review_comments" => true
          }
        )

      reviews = get_in(discussion, ["data", "discussion", "reviews"]) || []
      discussion_summary = get_in(discussion, ["data", "discussion", "summary"])
      approval_state_count = get_in(discussion_summary || %{}, ["reviewStateCounts", "approved"]) || 0
      assert is_map(discussion_summary)
      assert approval_state_count >= 1
      assert Map.get(discussion_summary, "approvalCount", 0) >= 1

      assert Enum.any?(reviews, fn review ->
               review["state"] == "APPROVED" and get_in(review, ["user", "login"]) == reviewer_login
             end)

      snapshot =
        execute_success!(
          context,
          "repo_change_proposal_snapshot",
          %{"number" => target, "include_discussion" => true, "include_checks" => false}
        )

      snapshot_reviews = get_in(snapshot, ["data", "discussion", "reviews"]) || []

      assert Enum.any?(snapshot_reviews, fn review ->
               review["state"] == "APPROVED" and get_in(review, ["user", "login"]) == reviewer_login
             end)

      close_target = get_in(snapshot, ["data", "changeProposal", "number"]) || target

      execute_success!(
        context,
        "repo_close_change_proposal",
        %{
          "number" => close_target,
          "comment" => "Closing temporary Symphony GitHub independent approval live probe."
        }
      )

      IO.puts(
        "github_independent_approval_live_probe " <>
          "repository=#{repository} branch=#{branch} head_sha=#{head_sha} " <>
          "change_proposal=#{change_proposal["url"]} reviewer=#{reviewer_login}"
      )
    after
      close_open_prs_for_branch(repository, branch)
      delete_remote_branch(repo_path, branch)
      File.rm_rf(root)
    end
  end

  defp dynamic_tool_context(repo_path, remote_url, repository, base_branch, branch_prefix) do
    repo_core = %{
      path: repo_path,
      base_branch: base_branch,
      remote: %{name: "origin", url: remote_url},
      branch: %{work_prefix: branch_prefix}
    }

    repo_provider =
      Map.put(repo_core, :provider, %{
        kind: "github",
        repository: repository
      })

    DynamicTool.capture_context(
      dynamic_tool_sources: [
        {SymphonyElixir.Repo.DynamicToolSource, repo_core},
        {SymphonyElixir.RepoProvider.DynamicToolSource, repo_provider}
      ]
    )
  end

  defp execute_success!(context, tool, arguments) do
    case DynamicTool.execute(context, tool, arguments) do
      {:success, payload} ->
        payload

      {:failure, payload} ->
        flunk("#{tool} failed: #{inspect(payload)}")

      {:error, reason} ->
        flunk("#{tool} errored: #{inspect(reason)}")
    end
  end

  defp clone_repo!(remote_url, base_branch, repo_path) do
    run!(
      "git",
      ["clone", "--depth", "1", "--branch", base_branch, remote_url, repo_path],
      "clone #{remote_url}##{base_branch}"
    )
  end

  defp configure_git_identity!(repo_path) do
    run!("git", ["-C", repo_path, "config", "user.email", "symphony-live@example.invalid"], "configure git email")
    run!("git", ["-C", repo_path, "config", "user.name", "Symphony Live Smoke"], "configure git user")
  end

  defp write_probe_file!(repo_path, repository, branch) do
    path = Path.join([repo_path, ".symphony-live-smoke", "#{safe_file_name(branch)}.txt"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    repository=#{repository}
    branch=#{branch}
    created_by=symphony_github_change_proposal_live_probe
    """)
  end

  defp live_pr_body(repository, branch) do
    """
    Temporary PR created by Symphony's GitHub typed change-proposal live smoke.

    Repository: #{repository}
    Branch: #{branch}

    The test closes this PR and deletes the branch during cleanup.
    """
    |> String.trim()
  end

  defp live_review_checks_pr_body(repository, branch) do
    """
    Temporary PR created by Symphony's GitHub review/check live smoke.

    Repository: #{repository}
    Branch: #{branch}

    The test reads the PR snapshot, discussion, and checks through typed repo
    tools, then closes this PR and deletes the branch during cleanup.
    """
    |> String.trim()
  end

  defp live_independent_approval_pr_body(repository, branch, reviewer_login) do
    """
    Temporary PR created by Symphony's GitHub independent approval live smoke.

    Repository: #{repository}
    Branch: #{branch}
    Expected reviewer: #{reviewer_login}

    The test submits an approval using an independent reviewer token, reads the
    approval back through typed repo-provider tools, then closes this PR and
    deletes the branch during cleanup.
    """
    |> String.trim()
  end

  defp submit_independent_approval!(reviewer_token, repository, target, branch) do
    run_with_token!(
      reviewer_token,
      "gh",
      [
        "pr",
        "review",
        to_string(target),
        "--repo",
        repository,
        "--approve",
        "--body",
        "Approving temporary Symphony independent approval live probe for #{branch}."
      ],
      "submit independent GitHub approval"
    )
  end

  defp gh_login!, do: gh_login!(nil)

  defp gh_login!(nil) do
    run_capture!("gh", ["api", "user", "--jq", ".login"], "read GitHub login")
    |> String.trim()
  end

  defp gh_login!(token) when is_binary(token) do
    token
    |> run_capture_with_token!("gh", ["api", "user", "--jq", ".login"], "read reviewer GitHub login")
    |> String.trim()
  end

  defp trigger_check_workflows(repository, branch) do
    repository
    |> check_workflows()
    |> Enum.each(fn workflow ->
      run!(
        "gh",
        ["workflow", "run", workflow, "--repo", repository, "--ref", branch],
        "trigger GitHub workflow #{workflow}"
      )
    end)
  end

  defp publish_success_status_check(repository, head_sha) when is_binary(head_sha) do
    if publish_status_check?() do
      run!(
        "gh",
        [
          "api",
          "repos/#{repository}/statuses/#{head_sha}",
          "-f",
          "state=success",
          "-f",
          "context=#{status_check_context()}",
          "-f",
          "description=Symphony disposable passing status for merge-gate live probe",
          "-f",
          "target_url=https://github.com/#{repository}/pulls"
        ],
        "publish GitHub status check"
      )
    end
  end

  defp publish_success_status_check(_repository, _head_sha), do: :ok

  defp publish_status_check? do
    live_env("SYMPHONY_GITHUB_PUBLISH_STATUS_CHECK", "1") == "1"
  end

  defp status_check_context do
    live_env("SYMPHONY_GITHUB_STATUS_CHECK_CONTEXT", "Symphony live gate probe")
  end

  defp check_workflows(repository) do
    "SYMPHONY_GITHUB_CHECK_WORKFLOWS"
    |> live_env(default_check_workflows(repository))
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp default_check_workflows(_repository), do: ""

  defp wait_for_passing_checks!(context, target) do
    deadline_ms = System.monotonic_time(:millisecond) + checks_timeout_ms()
    wait_for_passing_checks_until!(context, target, deadline_ms, nil)
  end

  defp wait_for_passing_checks_until!(context, target, deadline_ms, latest) do
    checks =
      execute_success!(
        context,
        "repo_read_change_proposal_checks",
        %{"number" => target}
      )

    runs = get_in(checks, ["data", "checks", "runs"]) || []
    latest_runs = if runs == [], do: latest || [], else: runs

    cond do
      passing_check_runs?(runs) ->
        checks

      System.monotonic_time(:millisecond) < deadline_ms ->
        Process.sleep(checks_poll_ms())
        wait_for_passing_checks_until!(context, target, deadline_ms, latest_runs)

      true ->
        flunk("expected passing checks, got: #{inspect(check_run_summary(latest_runs))}")
    end
  end

  defp passing_check_runs?(runs) when is_list(runs) and runs != [] do
    Enum.all?(runs, fn run ->
      run["status"] == "completed" and run["conclusion"] in ["success", "neutral", "skipped"]
    end)
  end

  defp passing_check_runs?(_runs), do: false

  defp check_run_summary(runs) when is_list(runs) do
    Enum.map(runs, fn run ->
      %{
        "name" => run["name"],
        "status" => run["status"],
        "conclusion" => run["conclusion"]
      }
    end)
  end

  defp check_run_summary(_runs), do: []

  defp close_open_prs_for_branch(repository, branch) do
    case CommandEnv.system_cmd(
           "gh",
           [
             "pr",
             "list",
             "--repo",
             repository,
             "--head",
             branch,
             "--state",
             "open",
             "--json",
             "number",
             "--jq",
             ".[].number"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&close_pr(repository, &1))

      _other ->
        :ok
    end
  end

  defp close_pr(repository, number) do
    CommandEnv.system_cmd(
      "gh",
      [
        "pr",
        "close",
        number,
        "--repo",
        repository,
        "--comment",
        "Closing temporary Symphony GitHub typed live probe."
      ],
      stderr_to_stdout: true
    )

    :ok
  end

  defp delete_remote_branch(repo_path, branch) do
    if File.dir?(Path.join(repo_path, ".git")) do
      CommandEnv.system_cmd(
        "git",
        ["-C", repo_path, "push", "origin", "--delete", branch],
        stderr_to_stdout: true
      )
    end

    :ok
  end

  defp run!(command, args, label) do
    case CommandEnv.system_cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("#{label} failed with exit #{status}: #{String.trim(output)}")
    end
  end

  defp run_with_token!(token, command, args, label) do
    case CommandEnv.system_cmd(command, args, env: [{"GH_TOKEN", token}], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("#{label} failed with exit #{status}: #{String.trim(output)}")
    end
  end

  defp run_capture!(command, args, label) do
    case CommandEnv.system_cmd(command, args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("#{label} failed with exit #{status}: #{String.trim(output)}")
    end
  end

  defp run_capture_with_token!(token, command, args, label) do
    case CommandEnv.system_cmd(command, args, env: [{"GH_TOKEN", token}], stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("#{label} failed with exit #{status}: #{String.trim(output)}")
    end
  end

  defp live_env(key, default) do
    case System.get_env(key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> default
          trimmed -> trimmed
        end

      _value ->
        default
    end
  end

  defp checks_timeout_ms, do: live_int_env("SYMPHONY_GITHUB_CHECKS_TIMEOUT_MS", @default_checks_timeout_ms)
  defp checks_poll_ms, do: live_int_env("SYMPHONY_GITHUB_CHECKS_POLL_MS", @default_checks_poll_ms)

  defp live_int_env(key, default) do
    case System.get_env(key) do
      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _other -> default
        end

      _value ->
        default
    end
  end

  defp required_live_env!(key) do
    case System.get_env(key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> flunk("expected #{key} to be set for live GitHub probe")
          trimmed -> trimmed
        end

      _value ->
        flunk("expected #{key} to be set for live GitHub probe")
    end
  end

  defp live_branch(prefix, slug \\ "github-change-proposal") do
    normalized_prefix =
      prefix
      |> String.trim()
      |> String.trim("/")
      |> String.replace(~r/[^A-Za-z0-9._\/-]/, "-")
      |> case do
        "" -> @default_branch_prefix
        value -> value
      end

    suffix = "#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
    "#{normalized_prefix}/#{slug}-#{suffix}"
  end

  defp safe_file_name(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9._-]/, "-")
    |> String.trim("-")
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
