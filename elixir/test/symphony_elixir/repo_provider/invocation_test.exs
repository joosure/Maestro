defmodule SymphonyElixir.RepoProvider.InvocationTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.Invocation

  test "parses provider overrides and pr-view query arguments" do
    assert {:ok,
            %Invocation{
              provider_override: "cnb",
              command: :pr_view,
              number: "42",
              json_fields: ["url", "state"],
              jq: ".url"
            }} =
             Invocation.parse(["--provider", "cnb", "pr-view", "42", "--json", "url,state", "-q", ".url"])
  end

  test "parses CNB PR mutation arguments" do
    assert {:ok,
            %Invocation{
              command: :pr_create,
              title: "Add CNB support",
              body: "body text",
              base: "main",
              head: "feature/cnb-provider"
            }} =
             Invocation.parse([
               "pr-create",
               "--title",
               "Add CNB support",
               "--body",
               "body text",
               "--base",
               "main",
               "--head",
               "feature/cnb-provider"
             ])

    assert {:ok,
            %Invocation{
              command: :pr_merge,
              number: "42",
              merge_style: "squash",
              subject: "Ship it",
              body: "merge body"
            }} =
             Invocation.parse(["pr-merge", "42", "--squash", "--subject", "Ship it", "--body", "merge body"])
  end

  test "parses pr-add-label arguments" do
    assert {:ok,
            %Invocation{
              command: :pr_add_label,
              label: "release-ready",
              number: "42"
            }} = Invocation.parse(["pr-add-label", "release-ready", "42"])

    assert {:ok,
            %Invocation{
              command: :pr_add_label,
              label: "release-ready"
            }} = Invocation.parse(["pr-add-label", "--label", "release-ready"])
  end

  test "parses review comment commands" do
    assert {:ok,
            %Invocation{
              command: :pr_issue_comments,
              number: "42",
              json_fields: ["id", "body"],
              jq: ".[0].id"
            }} =
             Invocation.parse(["pr-issue-comments", "42", "--json", "id,body", "-q", ".[0].id"])

    assert {:ok,
            %Invocation{
              command: :pr_add_issue_comment,
              number: "42",
              body: "[codex] acknowledged"
            }} =
             Invocation.parse([
               "pr-add-issue-comment",
               "42",
               "--body",
               "[codex] acknowledged"
             ])

    assert {:ok,
            %Invocation{
              command: :pr_reviews,
              number: "42",
              json_fields: ["id", "state"],
              jq: ".[0].state"
            }} =
             Invocation.parse(["pr-reviews", "42", "--json", "id,state", "-q", ".[0].state"])

    assert {:ok,
            %Invocation{
              command: :pr_review_comments,
              number: "42",
              json_fields: ["id", "body"],
              jq: ".[0].id"
            }} =
             Invocation.parse(["pr-review-comments", "42", "--json", "id,body", "-q", ".[0].id"])

    assert {:ok,
            %Invocation{
              command: :pr_reply_review_comment,
              comment_id: "101",
              number: "42",
              body: "[codex] acknowledged"
            }} =
             Invocation.parse([
               "pr-reply-review-comment",
               "101",
               "42",
               "--body",
               "[codex] acknowledged"
             ])
  end

  test "parses pr-close comment arguments" do
    assert {:ok,
            %Invocation{
              command: :pr_close,
              number: "42",
              comment: "restart from a fresh branch"
            }} = Invocation.parse(["pr-close", "42", "--comment", "restart from a fresh branch"])
  end

  test "parses CNB pr-checks flags and optional PR number" do
    assert {:ok,
            %Invocation{
              command: :pr_checks,
              watch?: true,
              json?: true,
              jq: ".[0].name"
            }} =
             Invocation.parse(["pr-checks", "--watch", "--json", "-q", ".[0].name"])

    assert {:ok,
            %Invocation{
              command: :pr_checks,
              number: "42",
              watch?: true,
              json?: true,
              jq: ".[0].name"
            }} =
             Invocation.parse(["pr-checks", "42", "--watch", "--json", "-q", ".[0].name"])
  end

  test "parses repo-provider pr-land-watch flags and optional PR number" do
    assert {:ok,
            %Invocation{
              command: :pr_land_watch,
              number: "42",
              poll_ms: 500,
              checks_appear_timeout_ms: 2_000
            }} =
             Invocation.parse([
               "pr-land-watch",
               "42",
               "--poll-ms",
               "500",
               "--checks-appear-timeout-ms",
               "2000"
             ])
  end

  test "parses repo-provider api arguments" do
    assert {:ok,
            %Invocation{
              command: :api,
              api_endpoint: "repos/{owner}/{repo}/issues/42/comments",
              api_method: "POST",
              api_fields: %{"body" => "hello", "work_mode" => "true"},
              jq: ".[0].id"
            }} =
             Invocation.parse([
               "api",
               "-X",
               "post",
               "repos/{owner}/{repo}/issues/42/comments",
               "-f",
               "body=hello",
               "-F",
               "work_mode=true",
               "--jq",
               ".[0].id"
             ])
  end

  test "rejects unsupported commands and missing option values" do
    assert {:error, %Error{exit_code: 64, message: "Unsupported command: unsupported"}} =
             Invocation.parse(["unsupported"])

    assert {:error, %Error{exit_code: 64, message: "Option --provider requires a value"}} =
             Invocation.parse(["--provider"])

    assert {:error, %Error{exit_code: 64, message: "Option --json requires a value"}} =
             Invocation.parse(["pr-view", "--json"])

    assert {:error, %Error{exit_code: 64, message: "Option --title requires a value"}} =
             Invocation.parse(["pr-create", "--title"])

    assert {:error, %Error{exit_code: 64, message: "pr-add-issue-comment requires --body or --body-file"}} =
             Invocation.parse(["pr-add-issue-comment", "42"])

    assert {:error, %Error{exit_code: 64, message: "pr-reply-review-comment requires a comment id"}} =
             Invocation.parse(["pr-reply-review-comment"])

    assert {:error, %Error{exit_code: 64, message: "pr-reply-review-comment requires --body or --body-file"}} =
             Invocation.parse(["pr-reply-review-comment", "101"])

    assert {:error, %Error{exit_code: 64, message: "Option --comment requires a value"}} =
             Invocation.parse(["pr-close", "--comment"])

    assert {:error, %Error{exit_code: 64, message: "pr-add-label requires a label"}} =
             Invocation.parse(["pr-add-label"])

    assert {:error, %Error{exit_code: 64, message: "Option --jq requires a value"}} =
             Invocation.parse(["pr-checks", "--jq"])

    assert {:error, %Error{exit_code: 64, message: "Option --poll-ms requires a value"}} =
             Invocation.parse(["pr-land-watch", "--poll-ms"])

    assert {:error, %Error{exit_code: 64, message: "repo-provider api requires an endpoint"}} =
             Invocation.parse(["api"])

    assert {:error, %Error{exit_code: 64, message: "run-view requires a run id"}} =
             Invocation.parse(["run-view"])

    assert {:error, %Error{exit_code: 64, message: "Invalid run-list limit: nope"}} =
             Invocation.parse(["run-list", "--limit", "nope"])
  end
end
