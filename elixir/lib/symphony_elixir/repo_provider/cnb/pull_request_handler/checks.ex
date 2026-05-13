defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler.Checks do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler.{Common, Resolution}

  @type repo_config :: map()

  @spec pr_checks(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def pr_checks(repo, repository, token, opts) do
    with {:ok, pull} <- Resolution.resolve_pull_for_mutation(repo, repository, token, opts),
         {:ok, number} <- Common.require_pull_number(pull, :pr_checks_pull),
         {:ok, payload} <-
           HttpClient.fetch_repo_json(
             repo,
             repository,
             token,
             "/-/pulls/#{number}/commit-statuses",
             %{},
             opts
           ) do
      {:ok, Normalizer.normalize_check_payload(payload)}
    end
  end
end
