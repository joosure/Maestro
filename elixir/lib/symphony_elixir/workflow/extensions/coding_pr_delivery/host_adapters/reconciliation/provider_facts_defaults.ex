defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProviderFactsDefaults do
  @moduledoc false

  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError

  @change_proposal_not_found_codes ~w(
    cnb_pull_not_found
    cnb_pull_not_found_for_branch
    cnb_pull_not_found_for_sha
    github_pr_not_found
  )a

  @spec pr_view(map(), keyword()) :: term()
  def pr_view(repo, opts), do: RepoProvider.pr_view(repo, opts)

  @spec pr_issue_comments(map(), keyword()) :: term()
  def pr_issue_comments(repo, opts), do: RepoProvider.pr_issue_comments(repo, opts)

  @spec pr_review_comments(map(), keyword()) :: term()
  def pr_review_comments(repo, opts), do: RepoProvider.pr_review_comments(repo, opts)

  @spec pr_reviews(map(), keyword()) :: term()
  def pr_reviews(repo, opts), do: RepoProvider.pr_reviews(repo, opts)

  @spec pr_checks(map(), keyword()) :: term()
  def pr_checks(repo, opts), do: RepoProvider.pr_checks(repo, opts)

  @spec provider_kind(map()) :: String.t() | nil
  def provider_kind(repo), do: RepoProvider.current_kind(repo)

  @spec repository(map()) :: String.t() | nil
  def repository(repo), do: RepoConfig.repository(repo)

  @spec normalize_error(map() | nil, atom(), term()) :: RepoProviderError.t()
  def normalize_error(repo, operation, reason), do: RepoProviderError.normalize(repo, operation, reason)

  @spec retryable_error?(RepoProviderError.t()) :: boolean()
  def retryable_error?(error), do: RepoProviderError.retryable?(error)

  @spec change_proposal_not_found?(term()) :: boolean()
  def change_proposal_not_found?(reason) do
    %RepoProviderError{code: code} = normalize_error(nil, :pr_view, reason)
    code in @change_proposal_not_found_codes
  end
end
