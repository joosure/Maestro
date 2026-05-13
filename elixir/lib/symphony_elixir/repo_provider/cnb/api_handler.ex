defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler do
  @moduledoc """
  API proxy and translation layer for the CNB adapter.

  Handles generic API calls and translates GitHub-style REST endpoints
  into equivalent CNB API calls.
  """

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.{IssueComments, ReviewComments, Reviews, Router}

  @type repo_config :: map()

  @spec api(repo_config(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  defdelegate api(repo, token, opts), to: Router

  @spec pr_issue_comments(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  defdelegate pr_issue_comments(repo, repository, token, opts), to: IssueComments, as: :list_for_pr

  @spec pr_add_issue_comment(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate pr_add_issue_comment(repo, repository, token, opts), to: IssueComments, as: :add_to_pr

  @spec pr_reviews(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  defdelegate pr_reviews(repo, repository, token, opts), to: Reviews, as: :list_for_pr

  @spec pr_review_comments(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  defdelegate pr_review_comments(repo, repository, token, opts), to: ReviewComments, as: :list_for_pr

  @spec pr_reply_review_comment(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate pr_reply_review_comment(repo, repository, token, opts), to: ReviewComments, as: :reply_to_pr
end
