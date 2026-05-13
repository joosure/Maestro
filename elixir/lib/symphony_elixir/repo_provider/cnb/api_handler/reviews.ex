defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.Reviews do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.Common
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec list_for_pr(repo_config(), String.t(), String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_for_pr(repo, repository, token, opts) do
    with {:ok, number} <- Common.resolve_pull_number(repo, repository, token, opts),
         {:ok, reviews} <- list_all(repo, repository, token, number, opts),
         {:ok, reviews} <- Common.maybe_slice(reviews, Common.pagination_fields(opts)) do
      {:ok, Enum.map(reviews, &Normalizer.normalize_review/1)}
    end
  end

  @spec translate(repo_config(), String.t(), String.t(), term(), atom(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def translate(repo, repository, token, number, :get, fields, opts) do
    with {:ok, {page, per_page}} <- Common.pagination_values(fields),
         {:ok, payload} <-
           HttpClient.request_repo_payload(
             repo,
             repository,
             token,
             :get,
             "/-/pulls/#{number}/reviews",
             %{"page" => page, "page_size" => per_page},
             nil,
             opts
           ),
         {:ok, reviews} <- Normalizer.expect_list(payload, :reviews) do
      {:ok, Enum.map(reviews, &Normalizer.normalize_review/1)}
    end
  end

  def translate(_repo, _repository, _token, _number, method, _fields, _opts) do
    {:error, Error.invalid_invocation("Unsupported CNB review method: #{Common.method_name(method)}")}
  end

  @spec list_all(repo_config(), String.t(), String.t(), term(), keyword()) :: {:ok, list()} | {:error, term()}
  def list_all(repo, repository, token, number, opts) do
    Common.fetch_pages([], 1, fn page ->
      with {:ok, payload} <-
             HttpClient.request_repo_payload(
               repo,
               repository,
               token,
               :get,
               "/-/pulls/#{number}/reviews",
               %{"page" => page, "page_size" => 100},
               nil,
               opts
             ),
           {:ok, reviews} <- Normalizer.expect_list(payload, :reviews) do
        {:ok, reviews, length(reviews) == 100}
      end
    end)
  end
end
