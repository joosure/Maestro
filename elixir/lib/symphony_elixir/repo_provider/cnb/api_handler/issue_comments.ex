defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.IssueComments do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.Common
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec list_for_pr(repo_config(), String.t(), String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_for_pr(repo, repository, token, opts) do
    with {:ok, number} <- Common.resolve_pull_number(repo, repository, token, opts),
         {:ok, comments} <- list_all(repo, repository, token, number, opts),
         {:ok, comments} <- Common.maybe_slice(comments, Common.pagination_fields(opts)) do
      {:ok, Enum.map(comments, &Normalizer.normalize_issue_comment/1)}
    end
  end

  @spec add_to_pr(repo_config(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_to_pr(repo, repository, token, opts) do
    with {:ok, body} <- Common.required_issue_comment_body(opts),
         {:ok, number} <- Common.resolve_pull_number(repo, repository, token, opts) do
      translate(repo, repository, token, number, :post, %{"body" => body}, opts)
    end
  end

  @spec translate(repo_config(), String.t(), String.t(), term(), atom(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def translate(repo, repository, token, number, :get, fields, opts) do
    with {:ok, payload} <-
           HttpClient.request_repo_payload(
             repo,
             repository,
             token,
             :get,
             "/-/pulls/#{number}/comments",
             Common.translate_query_fields(fields),
             nil,
             opts
           ),
         {:ok, comments} <- Normalizer.expect_list(payload, :issue_comments) do
      {:ok, Enum.map(comments, &Normalizer.normalize_issue_comment/1)}
    end
  end

  def translate(repo, repository, token, number, :post, fields, opts) do
    with {:ok, body} <- Common.required_field(fields, "body"),
         request_body <-
           Common.maybe_put_work_mode(%{"body" => body}, fields),
         {:ok, payload} <-
           HttpClient.request_repo_payload(
             repo,
             repository,
             token,
             :post,
             "/-/pulls/#{number}/comments",
             %{},
             request_body,
             opts
           ),
         {:ok, comment} <- Normalizer.expect_map(payload, :issue_comment) do
      {:ok, Normalizer.normalize_issue_comment(comment)}
    end
  end

  def translate(_repo, _repository, _token, _number, method, _fields, _opts) do
    {:error, Error.invalid_invocation("Unsupported CNB issue comment method: #{Common.method_name(method)}")}
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
               "/-/pulls/#{number}/comments",
               %{"page" => page, "page_size" => 100},
               nil,
               opts
             ),
           {:ok, comments} <- Normalizer.expect_list(payload, :issue_comments) do
        {:ok, comments, length(comments) == 100}
      end
    end)
  end
end
