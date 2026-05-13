defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.CheckRuns do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.Common
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec translate(repo_config(), String.t(), String.t(), String.t(), atom(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def translate(repo, repository, token, sha, :get, fields, opts) do
    with {:ok, {page, per_page}} <- Common.pagination_values(fields),
         {:ok, pull} <- PullRequestHandler.resolve_pull_by_sha(repo, repository, token, sha, opts),
         {:ok, number} <- Common.require_pull_number(pull, :check_runs_pull),
         {:ok, payload} <-
           HttpClient.fetch_repo_json(
             repo,
             repository,
             token,
             "/-/pulls/#{number}/commit-statuses",
             %{},
             opts
           ) do
      check_runs = Normalizer.normalize_check_payload(payload)

      {:ok,
       %{
         "check_runs" => Normalizer.slice_page(check_runs, page, per_page),
         "total_count" => length(check_runs)
       }}
    end
  end

  def translate(_repo, _repository, _token, _sha, method, _fields, _opts) do
    {:error, Error.invalid_invocation("Unsupported CNB check runs method: #{Common.method_name(method)}")}
  end
end
