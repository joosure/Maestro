defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler do
  @moduledoc """
  Pull request lifecycle operations for the CNB adapter.

  Handles resolution, creation, mutation, merging, and closing of
  pull requests through the CNB REST API. Called by `CNB.Adapter`
  for all PR-related callbacks.
  """

  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler.{BranchCleanup, Checks, Mutations, Resolution}

  @type repo_config :: map()

  @spec pr_view(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def pr_view(repo, repository, token, opts) do
    with {:ok, pull} <- Resolution.resolve_pull(repo, repository, token, opts) do
      {:ok, Normalizer.normalize_pull(repo, repository, pull)}
    end
  end

  @spec pr_create(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate pr_create(repo, repository, token, opts), to: Mutations

  @spec pr_edit(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate pr_edit(repo, repository, token, opts), to: Mutations

  @spec pr_close(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate pr_close(repo, repository, token, opts), to: Mutations

  @spec pr_merge(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate pr_merge(repo, repository, token, opts), to: Mutations

  @spec pr_checks(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  defdelegate pr_checks(repo, repository, token, opts), to: Checks

  @spec close_open_pull_requests_for_branch(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  defdelegate close_open_pull_requests_for_branch(repo, repository, token, branch, opts), to: BranchCleanup

  @spec resolve_pull(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate resolve_pull(repo, repository, token, opts), to: Resolution

  @spec resolve_pull_for_mutation(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate resolve_pull_for_mutation(repo, repository, token, opts), to: Resolution

  @spec resolve_pull_by_sha(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate resolve_pull_by_sha(repo, repository, token, sha, opts), to: Resolution

  @spec resolve_pull_for_branch(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate resolve_pull_for_branch(repo, repository, token, branch, opts), to: Resolution

  @spec list_pull_requests(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  defdelegate list_pull_requests(repo, repository, token, state, opts), to: Resolution
end
