defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler.Common do
  @moduledoc false

  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.Repo.Context, as: RepoContext
  alias SymphonyElixir.RepoProvider.CNB.Normalizer

  @type repo_config :: map()

  @spec require_pull_number(map(), atom()) :: {:ok, term()} | {:error, term()}
  def require_pull_number(pull, action) do
    case Normalizer.pull_number(pull) do
      nil -> {:error, {:cnb_unknown_payload, action, pull}}
      "" -> {:error, {:cnb_unknown_payload, action, pull}}
      number -> {:ok, number}
    end
  end

  @spec current_branch(repo_config(), keyword()) :: String.t() | nil
  def current_branch(repo, opts) do
    case TargetRepo.current_branch(RepoContext.path(repo, opts), opts) do
      {:ok, branch} ->
        branch

      {:error, _reason} ->
        nil
    end
  end

  @spec require_current_branch(repo_config(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def require_current_branch(repo, opts) do
    case current_branch(repo, opts) do
      branch when is_binary(branch) and branch != "" -> {:ok, branch}
      _other -> {:error, :cnb_current_branch_unavailable}
    end
  end

  @spec base_branch(repo_config(), keyword()) :: String.t()
  def base_branch(repo, opts), do: RepoContext.base_branch(repo, opts)

  @spec fetch_pages(list(), pos_integer(), function()) :: {:ok, list()} | {:error, term()}
  def fetch_pages(acc, page, fetcher) do
    case fetcher.(page) do
      {:ok, items, true} -> fetch_pages(acc ++ items, page + 1, fetcher)
      {:ok, items, false} -> {:ok, acc ++ items}
      {:error, _reason} = error -> error
    end
  end

  @spec first_present(term(), term()) :: term()
  def first_present(value, _default) when is_binary(value) and value != "", do: value
  def first_present(_value, default) when is_binary(default), do: default
end
