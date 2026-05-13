defmodule SymphonyElixir.RepoProviderCNBAdapterContractTest do
  use ExUnit.Case, async: false

  @missing_token_opts [token: nil]

  use SymphonyElixir.RepoProviderAdapterContract,
    adapter: SymphonyElixir.RepoProvider.CNB.Adapter,
    config: %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: "https://api.cnb.example.test"
      }
    },
    callback_opts: %{
      auth_status: @missing_token_opts,
      pr_view: @missing_token_opts,
      pr_create: @missing_token_opts,
      pr_edit: @missing_token_opts,
      pr_issue_comments: @missing_token_opts,
      pr_add_issue_comment: Keyword.merge(@missing_token_opts, body: "[codex] contract note"),
      pr_reviews: @missing_token_opts,
      pr_close: @missing_token_opts,
      pr_merge: @missing_token_opts,
      pr_checks: @missing_token_opts,
      pr_review_comments: @missing_token_opts,
      pr_reply_review_comment: Keyword.merge(@missing_token_opts, comment_id: "101", body: "[codex] acknowledged"),
      api: @missing_token_opts,
      run_list: @missing_token_opts,
      run_view: @missing_token_opts,
      close_open_pull_requests_for_branch: @missing_token_opts,
      healthcheck: @missing_token_opts
    }
end
