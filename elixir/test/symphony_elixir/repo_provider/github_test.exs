defmodule SymphonyElixir.RepoProvider.GitHubTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub.Adapter, as: GitHub

  test "validates config and parses GitHub repository slugs" do
    assert :ok == GitHub.validate_config(%{})

    assert :ok ==
             GitHub.validate_config(%{
               provider: %{options: %{required_pr_label: "release-ready"}}
             })

    assert GitHub.parse_repository_slug("https://github.com/acme/widgets.git") == "acme/widgets"
    assert GitHub.parse_repository_slug("git@github.com:acme/widgets.git") == "acme/widgets"
    assert GitHub.parse_repository_slug("https://cnb.cool/acme/widgets.git") == nil
  end

  test "resolves repository from opts, config, or origin remote" do
    assert GitHub.resolve_repository(%{}, repo: "explicit/widgets") == "explicit/widgets"

    assert GitHub.resolve_repository(%{},
             repo: "   ",
             command_runner: fn
               "git", ["remote", "get-url", "origin"] ->
                 {:ok, "git@github.com:derived/widgets.git\n"}
             end
           ) == "derived/widgets"

    assert GitHub.resolve_repository(%{provider: %{repository: "configured/widgets"}}) ==
             "configured/widgets"

    assert GitHub.resolve_repository(%{"provider" => %{"repository" => "string/widgets"}}) ==
             "string/widgets"

    assert GitHub.resolve_repository(%{},
             command_runner: fn
               "git", ["remote", "get-url", "origin"] ->
                 {:ok, "git@github.com:derived/widgets.git\n"}
             end
           ) == "derived/widgets"

    assert GitHub.resolve_repository(%{},
             command_runner: fn
               "git", ["remote", "get-url", "origin"] -> {:error, {1, "boom"}}
             end
           ) == nil

    repo_path = tmp_dir!("github-configured-remote")

    assert GitHub.resolve_repository(%{path: repo_path, remote: %{name: "upstream"}},
             command_runner: fn
               "git", ["-C", ^repo_path, "remote", "get-url", "upstream"] ->
                 {:ok, "git@github.com:configured-remote/widgets.git\n"}
             end
           ) == "configured-remote/widgets"

    assert GitHub.configured_repository(%{provider: %{repository: "configured/widgets"}}) ==
             "configured/widgets"

    assert GitHub.configured_repository(%{"provider" => %{"repository" => "string/widgets"}}) ==
             "string/widgets"

    assert GitHub.configured_repository(%{}) == nil
  end

  test "no-ops when gh is unavailable or auth fails" do
    with_empty_path(fn ->
      assert :ok == GitHub.close_open_pull_requests_for_branch(%{}, "feature/no-gh")
      assert GitHub.resolve_repository(%{}) == nil
    end)

    assert :ok ==
             GitHub.close_open_pull_requests_for_branch(%{}, "feature/no-gh", find_executable: fn "gh" -> nil end)

    assert :ok ==
             GitHub.close_open_pull_requests_for_branch(%{}, "feature/no-auth",
               find_executable: fn "gh" -> "/usr/bin/gh" end,
               command_runner: fn
                 "gh", ["auth", "status"] -> {:error, {1, "denied"}}
               end
             )
  end

  test "fails GitHub commands explicitly when repository slug cannot be resolved" do
    assert {:error,
            %Error{
              code: :missing_github_repository_slug,
              message: "GitHub provider requires a repository slug. Set repo.provider.repository or configure a GitHub remote."
            }} =
             GitHub.pr_view(%{},
               command_runner: fn
                 "git", ["remote", "get-url", "origin"] -> {:error, {1, "boom"}}
               end
             )
  end

  test "ignores list failures and formats close failures with or without output" do
    assert :ok ==
             GitHub.close_open_pull_requests_for_branch(%{}, "feature/list-fails",
               repo: "acme/widgets",
               find_executable: fn "gh" -> "/usr/bin/gh" end,
               command_runner: fn
                 "gh", ["auth", "status"] -> {:ok, ""}
                 "gh", ["pr", "list" | _rest] -> {:error, {1, "boom"}}
               end
             )

    parent = self()

    assert :ok ==
             GitHub.close_open_pull_requests_for_branch(
               %{provider: %{repository: "acme/widgets"}},
               "feature/workpad",
               find_executable: fn "gh" -> "/usr/bin/gh" end,
               command_runner: fn
                 "gh", ["auth", "status"] ->
                   {:ok, ""}

                 "gh",
                 [
                   "pr",
                   "list",
                   "--repo",
                   "acme/widgets",
                   "--head",
                   "feature/workpad",
                   "--state",
                   "open",
                   "--json",
                   "number",
                   "--jq",
                   ".[].number"
                 ] ->
                   {:ok, "101\n102\n103\n"}

                 "gh", ["pr", "close", "101", "--repo", "acme/widgets", "--comment", comment] ->
                   send(parent, {:close_comment, comment})
                   {:ok, ""}

                 "gh", ["pr", "close", "102", "--repo", "acme/widgets", "--comment", _comment] ->
                   {:error, {17, ""}}

                 "gh", ["pr", "close", "103", "--repo", "acme/widgets", "--comment", _comment] ->
                   {:error, {18, "boom\n"}}
               end,
               info: fn message -> send(parent, {:info, message}) end,
               error: fn message -> send(parent, {:error, message}) end
             )

    assert_received {:close_comment, "Closing because the issue for branch feature/workpad entered a terminal state without merge."}

    assert_received {:info, "Closed PR #101 for branch feature/workpad"}
    assert_received {:error, "Failed to close PR #102 for branch feature/workpad: exit 17"}

    assert_received {:error, "Failed to close PR #103 for branch feature/workpad: exit 18 output=\"boom\""}
  end

  test "runs GitHub PR write commands through gh with normalized URL output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh",
      [
        "pr",
        "create",
        "--repo",
        "acme/widgets",
        "--title",
        "Add feature",
        "--body",
        "body",
        "--base",
        "main",
        "--head",
        "feature"
      ] ->
        send(parent, :created)
        {:ok, "https://github.com/acme/widgets/pull/42\n"}

      "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", "url", "--jq", ".url"] ->
        {:ok, "https://github.com/acme/widgets/pull/42\n"}

      "gh",
      [
        "pr",
        "edit",
        "42",
        "--repo",
        "acme/widgets",
        "--title",
        "Updated",
        "--body",
        "new body",
        "--base",
        "develop"
      ] ->
        send(parent, :edited)
        {:ok, ""}

      "gh",
      [
        "pr",
        "merge",
        "42",
        "--repo",
        "acme/widgets",
        "--squash",
        "--subject",
        "Ship it",
        "--body",
        "Merged by CLI"
      ] ->
        send(parent, :merged)
        {:ok, ""}

      "gh", ["pr", "close", "42", "--repo", "acme/widgets"] ->
        send(parent, :closed)
        {:ok, ""}
    end

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_create(repo,
               title: "Add feature",
               body: "body",
               base: "main",
               head: "feature",
               command_runner: runner
             )

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_edit(repo,
               number: "42",
               title: "Updated",
               body: "new body",
               base: "develop",
               command_runner: runner
             )

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_merge(repo,
               number: "42",
               merge_style: "squash",
               subject: "Ship it",
               body: "Merged by CLI",
               command_runner: runner
             )

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_close(repo, number: "42", command_runner: runner)

    assert_received :created
    assert_received :edited
    assert_received :merged
    assert_received :closed
  end

  test "uses the current branch for GitHub PR commands when the number is omitted" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "git", ["branch", "--show-current"] ->
        {:ok, "feature/current-branch\n"}

      "gh",
      [
        "pr",
        "view",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--json",
        "number,url,state,title,body,headRefName,headRefOid,baseRefName,mergeable,mergeStateStatus"
      ] ->
        {:ok,
         Jason.encode!(%{
           "number" => 77,
           "url" => "https://github.com/acme/widgets/pull/77",
           "state" => "OPEN",
           "title" => "Current branch PR",
           "body" => "body",
           "headRefName" => "feature/current-branch",
           "headRefOid" => "abc123",
           "baseRefName" => "main",
           "mergeable" => "MERGEABLE",
           "mergeStateStatus" => "CLEAN"
         })}

      "gh",
      [
        "pr",
        "view",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--json",
        "url",
        "--jq",
        ".url"
      ] ->
        {:ok, "https://github.com/acme/widgets/pull/77\n"}

      "gh",
      [
        "pr",
        "view",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--json",
        "number",
        "--jq",
        ".number"
      ] ->
        {:ok, "77\n"}

      "gh",
      [
        "pr",
        "checks",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--json",
        "bucket,completedAt,description,link,name,startedAt,state,workflow"
      ] ->
        {:ok,
         Jason.encode!([
           %{
             "bucket" => "pass",
             "completedAt" => "2026-04-23T00:21:00Z",
             "description" => "green",
             "link" => "https://ci.example.test/runs/1",
             "name" => "ci",
             "startedAt" => "2026-04-23T00:20:00Z",
             "state" => "SUCCESS"
           }
         ])}

      "gh", ["pr", "edit", "feature/current-branch", "--repo", "acme/widgets", "--body", "updated body"] ->
        send(parent, :edited)
        {:ok, ""}

      "gh",
      [
        "pr",
        "edit",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--add-label",
        "release-ready"
      ] ->
        send(parent, :labeled)
        {:ok, ""}

      "gh",
      [
        "pr",
        "merge",
        "feature/current-branch",
        "--repo",
        "acme/widgets",
        "--squash",
        "--subject",
        "Ship it",
        "--body",
        "Merged by CLI"
      ] ->
        send(parent, :merged)
        {:ok, ""}

      "gh", ["pr", "close", "feature/current-branch", "--repo", "acme/widgets"] ->
        send(parent, :closed)
        {:ok, ""}

      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/77/reviews",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok,
         Jason.encode!([
           %{
             "id" => 9001,
             "body" => "Looks good",
             "submitted_at" => "2026-04-24T00:00:00Z",
             "state" => "approved",
             "user" => %{"login" => "reviewer", "type" => "User"}
           }
         ])}
    end

    assert {:ok,
            %{
              "number" => 77,
              "url" => "https://github.com/acme/widgets/pull/77",
              "headRefName" => "feature/current-branch"
            }} =
             GitHub.pr_view(repo, command_runner: runner)

    assert {:ok,
            [
              %{
                "name" => "ci",
                "status" => "completed",
                "conclusion" => "success",
                "details_url" => "https://ci.example.test/runs/1",
                "summary" => "green"
              }
            ]} = GitHub.pr_checks(repo, command_runner: runner)

    assert {:ok, "https://github.com/acme/widgets/pull/77"} =
             GitHub.pr_edit(repo, body: "updated body", command_runner: runner)

    assert {:ok, "https://github.com/acme/widgets/pull/77"} =
             GitHub.pr_add_label(repo, label: "release-ready", command_runner: runner)

    assert {:ok,
            [
              %{
                "id" => 9001,
                "body" => "Looks good",
                "created_at" => "2026-04-24T00:00:00Z",
                "submitted_at" => "2026-04-24T00:00:00Z",
                "state" => "APPROVED",
                "user" => %{"login" => "reviewer", "type" => "User"}
              }
            ]} = GitHub.pr_reviews(repo, command_runner: runner)

    assert {:ok, "https://github.com/acme/widgets/pull/77"} =
             GitHub.pr_merge(repo,
               merge_style: "squash",
               subject: "Ship it",
               body: "Merged by CLI",
               command_runner: runner
             )

    assert {:ok, "https://github.com/acme/widgets/pull/77"} =
             GitHub.pr_close(repo, command_runner: runner)

    assert_received :edited
    assert_received :labeled
    assert_received :merged
    assert_received :closed
  end

  test "fails GitHub PR commands clearly when the current branch cannot be resolved" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              code: :github_current_branch_required,
              message: "GitHub PR commands without an explicit number require a current git branch"
            }} =
             GitHub.pr_view(repo,
               command_runner: fn
                 "git", ["branch", "--show-current"] -> {:ok, "\n"}
               end
             )
  end

  test "uses configured repo path when resolving implicit GitHub PR target" do
    repo_path = tmp_dir!("github-current-branch")
    repo = %{path: repo_path, provider: %{kind: "github", repository: "acme/widgets"}}

    runner = fn
      "git", ["-C", ^repo_path, "branch", "--show-current"] ->
        {:ok, "feature/context-path\n"}

      "gh", ["pr", "view", "feature/context-path", "--repo", "acme/widgets", "--json", _fields] ->
        {:ok, Jason.encode!(%{"url" => "https://github.com/acme/widgets/pull/42"})}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:ok, %{"url" => "https://github.com/acme/widgets/pull/42"}} =
             GitHub.pr_view(repo, command_runner: runner)
  end

  test "maps GitHub PR not-found output separately from view failures" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              code: :github_pr_not_found,
              message: "No GitHub pull request found for the requested target.",
              details: %{output: "no pull requests found for branch \"feature/no-pr\""}
            }} =
             GitHub.pr_view(repo,
               number: "42",
               command_runner: fn
                 "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", _fields] ->
                   {:error, {1, "no pull requests found for branch \"feature/no-pr\"\n"}}
               end
             )

    assert {:error,
            %Error{
              code: :github_pr_view_failed,
              message: "GraphQL: timeout"
            }} =
             GitHub.pr_view(repo,
               number: "42",
               command_runner: fn
                 "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", _fields] ->
                   {:error, {1, "GraphQL: timeout\n"}}
               end
             )
  end

  test "validates GitHub pr-edit locally before invoking gh" do
    assert {:error,
            %Error{
              exit_code: 64,
              message: "GitHub pr-edit requires at least one editable field"
            }} =
             GitHub.pr_edit(%{provider: %{kind: "github", repository: "acme/widgets"}},
               number: "42",
               command_runner: fn _command, _args ->
                 flunk("gh should not be invoked for invalid pr-edit")
               end
             )
  end

  test "runs GitHub pr-add-label through gh with normalized URL output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", "url", "--jq", ".url"] ->
        {:ok, "https://github.com/acme/widgets/pull/42\n"}

      "gh", ["pr", "edit", "42", "--repo", "acme/widgets", "--add-label", "release-ready"] ->
        send(parent, :labeled)
        {:ok, ""}
    end

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_add_label(repo,
               number: "42",
               label: "release-ready",
               command_runner: runner
             )

    assert_received :labeled
  end

  test "runs GitHub pr-close comment through gh with normalized URL output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", "url", "--jq", ".url"] ->
        {:ok, "https://github.com/acme/widgets/pull/42\n"}

      "gh",
      [
        "pr",
        "close",
        "42",
        "--repo",
        "acme/widgets",
        "--comment",
        "[codex] restarting from a fresh branch"
      ] ->
        send(parent, :closed_with_comment)
        {:ok, ""}
    end

    assert {:ok, "https://github.com/acme/widgets/pull/42"} =
             GitHub.pr_close(repo,
               number: "42",
               comment: "[codex] restarting from a fresh branch",
               command_runner: runner
             )

    assert_received :closed_with_comment
  end

  test "validates GitHub pr-add-label locally before invoking gh" do
    assert {:error,
            %Error{
              exit_code: 64,
              message: "GitHub pr-add-label requires a non-empty label"
            }} =
             GitHub.pr_add_label(%{provider: %{kind: "github", repository: "acme/widgets"}},
               number: "42",
               label: "",
               command_runner: fn _command, _args ->
                 flunk("gh should not be invoked for invalid pr-add-label")
               end
             )
  end

  test "normalizes GitHub pr-checks JSON including pending gh exit status" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    runner = fn
      "gh",
      [
        "pr",
        "checks",
        "42",
        "--repo",
        "acme/widgets",
        "--json",
        "bucket,completedAt,description,link,name,startedAt,state,workflow"
      ] ->
        {:error,
         {8,
          Jason.encode!([
            %{
              "bucket" => "pass",
              "completedAt" => "2026-04-23T00:21:00Z",
              "description" => "green",
              "link" => "https://ci.example.test/runs/1",
              "name" => "ci",
              "startedAt" => "2026-04-23T00:20:00Z",
              "state" => "SUCCESS"
            },
            %{
              "bucket" => "pending",
              "description" => "still running",
              "name" => "lint",
              "state" => "PENDING"
            }
          ])}}
    end

    assert {:ok,
            [
              %{
                "name" => "ci",
                "status" => "completed",
                "conclusion" => "success",
                "details_url" => "https://ci.example.test/runs/1",
                "summary" => "green"
              },
              %{
                "name" => "lint",
                "status" => "in_progress",
                "conclusion" => nil,
                "summary" => "still running"
              }
            ]} = GitHub.pr_checks(repo, number: "42", command_runner: runner)
  end

  test "maps GitHub no-checks output to an empty check list" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    runner = fn
      "gh",
      [
        "pr",
        "checks",
        "42",
        "--repo",
        "acme/widgets",
        "--json",
        "bucket,completedAt,description,link,name,startedAt,state,workflow"
      ] ->
        {:error, {1, "no checks reported on the 'feature/no-ci' branch\n"}}
    end

    assert {:ok, []} = GitHub.pr_checks(repo, number: "42", command_runner: runner)
  end

  test "runs GitHub api through gh with placeholder expansion and decoded JSON output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/issues/42/comments",
        "--method",
        "POST",
        "-F",
        "body=hello",
        "-F",
        "per_page=2"
      ] ->
        send(parent, :api_called)
        {:ok, ~s([{"id":55,"body":"hello"}]\n)}
    end

    assert {:ok, [%{"id" => 55, "body" => "hello"}]} =
             GitHub.api(repo,
               endpoint: "repos/{owner}/{repo}/issues/42/comments",
               method: "POST",
               fields: %{"per_page" => "2", "body" => "hello"},
               command_runner: runner
             )

    assert_received :api_called
  end

  test "surfaces GitHub api transport and payload failures clearly" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    assert {:error, %Error{code: :missing_tooling, exit_code: 64}} =
             GitHub.api(repo,
               endpoint: "repos/{owner}/{repo}",
               command_runner: fn _command, _args -> {:error, {:enoent, ""}} end
             )

    assert {:error, %Error{code: :github_api_failed, message: "boom"}} =
             GitHub.api(repo,
               endpoint: "repos/{owner}/{repo}",
               command_runner: fn
                 "gh", ["api", "repos/acme/widgets", "--method", "GET"] -> {:error, {1, "boom\n"}}
               end
             )

    assert {:error, %Error{code: :github_invalid_payload}} =
             GitHub.api(repo,
               endpoint: "repos/{owner}/{repo}",
               command_runner: fn
                 "gh", ["api", "repos/acme/widgets", "--method", "GET"] -> {:ok, "not-json\n"}
               end
             )
  end

  test "lists GitHub issue comments across pages and adds top-level issue comments through dedicated commands" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => id,
          "body" => "top-level note #{id}",
          "created_at" => "2026-04-23T00:10:00Z",
          "updated_at" => "2026-04-23T00:10:00Z",
          "user" => %{"login" => "reviewer", "type" => "User"}
        }
      end)

    page_two = [
      %{
        "id" => 101,
        "body" => "top-level note 101",
        "created_at" => "2026-04-23T00:11:00Z",
        "updated_at" => "2026-04-23T00:11:00Z",
        "user" => %{"login" => "reviewer", "type" => "User"}
      }
    ]

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/issues/42/comments",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        send(parent, :issue_comments_page_one_called)
        {:ok, Jason.encode!(page_one)}

      "gh",
      [
        "api",
        "repos/acme/widgets/issues/42/comments",
        "--method",
        "GET",
        "-F",
        "page=2",
        "-F",
        "per_page=100"
      ] ->
        send(parent, :issue_comments_page_two_called)
        {:ok, Jason.encode!(page_two)}

      "gh",
      [
        "api",
        "repos/acme/widgets/issues/42/comments",
        "--method",
        "POST",
        "-F",
        "body=[codex] acknowledged"
      ] ->
        send(parent, :issue_comment_created)

        {:ok,
         Jason.encode!(%{
           "id" => 102,
           "body" => "[codex] acknowledged",
           "created_at" => "2026-04-23T00:12:00Z",
           "updated_at" => "2026-04-23T00:12:00Z",
           "user" => %{"login" => "codex", "type" => "Bot"}
         })}
    end

    assert {:ok, comments} = GitHub.pr_issue_comments(repo, number: "42", command_runner: runner)
    assert length(comments) == 101
    assert hd(comments)["id"] == 1
    assert List.last(comments)["id"] == 101

    assert {:ok,
            %{
              "id" => 102,
              "body" => "[codex] acknowledged",
              "user" => %{"login" => "codex", "type" => "Bot"}
            }} =
             GitHub.pr_add_issue_comment(repo,
               number: "42",
               body: "[codex] acknowledged",
               command_runner: runner
             )

    assert_received :issue_comments_page_one_called
    assert_received :issue_comments_page_two_called
    assert_received :issue_comment_created
  end

  test "validates GitHub issue comment inputs before invoking gh" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              exit_code: 64,
              message: "GitHub pr-add-issue-comment requires a non-empty body"
            }} =
             GitHub.pr_add_issue_comment(repo,
               body: "",
               command_runner: fn _command, _args ->
                 flunk("gh should not be invoked without an issue comment body")
               end
             )
  end

  test "lists GitHub reviews through the dedicated pr-reviews command" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/reviews",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        send(parent, :reviews_called)

        {:ok,
         Jason.encode!([
           %{
             "id" => 9,
             "body" => "looks good",
             "submitted_at" => "2026-04-23T00:05:00Z",
             "state" => "approved",
             "user" => %{"login" => "reviewer", "type" => "User"}
           }
         ])}
    end

    assert {:ok,
            [
              %{
                "id" => 9,
                "body" => "looks good",
                "submitted_at" => "2026-04-23T00:05:00Z",
                "state" => "APPROVED",
                "user" => %{"login" => "reviewer", "type" => "User"}
              }
            ]} = GitHub.pr_reviews(repo, number: "42", command_runner: runner)

    assert_received :reviews_called
  end

  test "aggregates GitHub reviews across pages by default" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => id,
          "body" => "review #{id}",
          "submitted_at" => "2026-04-23T00:05:00Z",
          "state" => "commented",
          "user" => %{"login" => "reviewer-#{id}", "type" => "User"}
        }
      end)

    page_two = [
      %{
        "id" => 101,
        "body" => "review 101",
        "submitted_at" => "2026-04-23T00:05:00Z",
        "state" => "approved",
        "user" => %{"login" => "reviewer-101", "type" => "User"}
      }
    ]

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/reviews",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!(page_one)}

      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/reviews",
        "--method",
        "GET",
        "-F",
        "page=2",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!(page_two)}
    end

    assert {:ok, reviews} = GitHub.pr_reviews(repo, number: "42", command_runner: runner)
    assert length(reviews) == 101
    assert hd(reviews)["id"] == 1
    assert List.last(reviews)["id"] == 101
    assert List.last(reviews)["state"] == "APPROVED"
  end

  test "submits GitHub review decisions through typed provider operation" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/reviews",
        "--method",
        "POST",
        "-F",
        "body=Please address this before merge.",
        "-F",
        "event=REQUEST_CHANGES"
      ] ->
        send(parent, :review_submitted)

        {:ok,
         Jason.encode!(%{
           "id" => 19,
           "body" => "Please address this before merge.",
           "submitted_at" => "2026-04-23T00:15:00Z",
           "state" => "CHANGES_REQUESTED",
           "user" => %{"login" => "reviewer", "type" => "User"}
         })}
    end

    assert {:ok,
            %{
              "id" => 19,
              "body" => "Please address this before merge.",
              "state" => "CHANGES_REQUESTED",
              "user" => %{"login" => "reviewer", "type" => "User"}
            }} =
             GitHub.pr_submit_review(repo,
               number: "42",
               event: "request_changes",
               body: "Please address this before merge.",
               command_runner: runner
             )

    assert_received :review_submitted
  end

  test "lists and replies to GitHub review comments through dedicated commands" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}
    parent = self()

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/comments",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        send(parent, :review_comments_called)

        {:ok,
         Jason.encode!([
           %{
             "id" => 101,
             "body" => "inline note",
             "created_at" => "2026-04-23T00:10:00Z",
             "updated_at" => "2026-04-23T00:10:00Z",
             "path" => "lib/example.ex",
             "commit_id" => "abc123",
             "pull_request_review_id" => 9,
             "in_reply_to_id" => nil,
             "user" => %{"login" => "reviewer", "type" => "User"}
           }
         ])}

      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/comments",
        "--method",
        "POST",
        "-F",
        "body=[codex] acknowledged",
        "-F",
        "in_reply_to=101"
      ] ->
        send(parent, :review_reply_called)

        {:ok,
         Jason.encode!(%{
           "id" => 102,
           "body" => "[codex] acknowledged",
           "created_at" => "2026-04-23T00:12:00Z",
           "updated_at" => "2026-04-23T00:12:00Z",
           "path" => "lib/example.ex",
           "commit_id" => "abc123",
           "pull_request_review_id" => 9,
           "in_reply_to_id" => 101,
           "user" => %{"login" => "codex", "type" => "Bot"}
         })}
    end

    assert {:ok,
            [
              %{
                "id" => 101,
                "body" => "inline note",
                "path" => "lib/example.ex",
                "commit_id" => "abc123",
                "pull_request_review_id" => 9,
                "user" => %{"login" => "reviewer", "type" => "User"}
              }
            ]} =
             GitHub.pr_review_comments(repo, number: "42", command_runner: runner)

    assert {:ok,
            %{
              "id" => 102,
              "body" => "[codex] acknowledged",
              "in_reply_to_id" => 101,
              "user" => %{"login" => "codex", "type" => "Bot"}
            }} =
             GitHub.pr_reply_review_comment(repo,
               number: "42",
               comment_id: "101",
               body: "[codex] acknowledged",
               command_runner: runner
             )

    assert_received :review_comments_called
    assert_received :review_reply_called
  end

  test "aggregates GitHub review comments across pages by default" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => id,
          "body" => "inline note #{id}",
          "path" => "lib/example.ex",
          "commit_id" => "abc123",
          "pull_request_review_id" => 9,
          "user" => %{"login" => "reviewer", "type" => "User"}
        }
      end)

    page_two = [
      %{
        "id" => 101,
        "body" => "inline note 101",
        "path" => "lib/example.ex",
        "commit_id" => "abc123",
        "pull_request_review_id" => 9,
        "user" => %{"login" => "reviewer", "type" => "User"}
      }
    ]

    runner = fn
      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/comments",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!(page_one)}

      "gh",
      [
        "api",
        "repos/acme/widgets/pulls/42/comments",
        "--method",
        "GET",
        "-F",
        "page=2",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!(page_two)}
    end

    assert {:ok, comments} = GitHub.pr_review_comments(repo, number: "42", command_runner: runner)
    assert length(comments) == 101
    assert hd(comments)["id"] == 1
    assert List.last(comments)["id"] == 101
  end

  test "validates GitHub review comment reply inputs before invoking gh" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              exit_code: 64,
              message: "GitHub pr-reply-review-comment requires a comment id"
            }} =
             GitHub.pr_reply_review_comment(repo,
               body: "[codex] acknowledged",
               command_runner: fn _command, _args ->
                 flunk("gh should not be invoked without a review comment id")
               end
             )

    assert {:error,
            %Error{
              exit_code: 64,
              message: "GitHub pr-reply-review-comment requires a non-empty body"
            }} =
             GitHub.pr_reply_review_comment(repo,
               comment_id: "101",
               body: "",
               command_runner: fn _command, _args ->
                 flunk("gh should not be invoked without a reply body")
               end
             )
  end

  test "normalizes GitHub run-list output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    runner = fn
      "gh",
      [
        "run",
        "list",
        "--repo",
        "acme/widgets",
        "--json",
        "attempt,conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,number,status,updatedAt,url,workflowName",
        "--branch",
        "main",
        "--limit",
        "5"
      ] ->
        {:ok,
         Jason.encode!([
           %{
             "attempt" => 1,
             "conclusion" => "success",
             "createdAt" => "2026-04-24T03:17:24Z",
             "databaseId" => 24_870_399_231,
             "displayTitle" => "Triage Scheduled Tasks",
             "event" => "schedule",
             "headBranch" => "main",
             "headSha" => "352a00e83c1c0a9723c5fb863db1fa65157e4d2a",
             "number" => 101,
             "status" => "completed",
             "updatedAt" => "2026-04-24T03:17:36Z",
             "url" => "https://github.com/acme/widgets/actions/runs/24870399231",
             "workflowName" => "Triage Scheduled Tasks"
           }
         ])}
    end

    assert {:ok,
            [
              %{
                "id" => 24_870_399_231,
                "title" => "Triage Scheduled Tasks",
                "status" => "completed",
                "conclusion" => "success",
                "rawStatus" => "success",
                "headBranch" => "main",
                "headSha" => "352a00e83c1c0a9723c5fb863db1fa65157e4d2a",
                "workflowName" => "Triage Scheduled Tasks"
              }
            ]} =
             GitHub.run_list(repo, branch: "main", limit: 5, command_runner: runner)
  end

  test "normalizes GitHub run-view summary and log output" do
    repo = %{provider: %{kind: "github", repository: "acme/widgets"}}

    runner = fn
      "gh",
      [
        "run",
        "view",
        "24870399231",
        "--repo",
        "acme/widgets",
        "--json",
        "attempt,conclusion,createdAt,databaseId,displayTitle,event,headBranch,headSha,jobs,number,startedAt,status,updatedAt,url,workflowName"
      ] ->
        {:ok,
         Jason.encode!(%{
           "attempt" => 1,
           "conclusion" => "success",
           "createdAt" => "2026-04-24T03:17:24Z",
           "databaseId" => 24_870_399_231,
           "displayTitle" => "Triage Scheduled Tasks",
           "event" => "schedule",
           "headBranch" => "main",
           "headSha" => "352a00e83c1c0a9723c5fb863db1fa65157e4d2a",
           "jobs" => [
             %{
               "completedAt" => "2026-04-24T03:17:35Z",
               "conclusion" => "success",
               "databaseId" => 72_815_466_837,
               "name" => "no-response / noResponse",
               "startedAt" => "2026-04-24T03:17:28Z",
               "status" => "completed",
               "steps" => [
                 %{
                   "completedAt" => "2026-04-24T03:17:30Z",
                   "conclusion" => "success",
                   "name" => "Set up job",
                   "number" => 1,
                   "startedAt" => "2026-04-24T03:17:29Z",
                   "status" => "completed"
                 }
               ],
               "url" => "https://github.com/acme/widgets/actions/runs/24870399231/job/72815466837"
             }
           ],
           "number" => 101,
           "startedAt" => "2026-04-24T03:17:25Z",
           "status" => "completed",
           "updatedAt" => "2026-04-24T03:17:36Z",
           "url" => "https://github.com/acme/widgets/actions/runs/24870399231",
           "workflowName" => "Triage Scheduled Tasks"
         })}

      "gh", ["run", "view", "24870399231", "--repo", "acme/widgets", "--log"] ->
        {:ok, "job-1\tUNKNOWN STEP\t2026-04-24T03:17:29Z Starting\n"}
    end

    assert {:ok,
            %{
              "id" => 24_870_399_231,
              "status" => "completed",
              "conclusion" => "success",
              "jobTotalCount" => 1,
              "jobSuccessCount" => 1,
              "jobFailCount" => 0,
              "jobs" => [
                %{
                  "id" => 72_815_466_837,
                  "name" => "no-response / noResponse",
                  "status" => "completed",
                  "conclusion" => "success"
                }
              ]
            }} =
             GitHub.run_view(repo, run_id: "24870399231", command_runner: runner)

    assert {:ok, log_output} =
             GitHub.run_view(repo, run_id: "24870399231", log?: true, command_runner: runner)

    assert log_output =~ "Run 24870399231: success"
    assert log_output =~ "Workflow: Triage Scheduled Tasks"
    assert log_output =~ "job-1\tUNKNOWN STEP"
  end

  defp with_empty_path(fun) do
    previous_path = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      fun.()
    after
      case previous_path do
        nil -> System.delete_env("PATH")
        value -> System.put_env("PATH", value)
      end
    end
  end

  defp tmp_dir!(name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "symphony-github-provider-#{name}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
