defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.ReviewComments do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.{Common, Reviews}
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec list_for_pr(repo_config(), String.t(), String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def list_for_pr(repo, repository, token, opts) do
    with {:ok, number} <- Common.resolve_pull_number(repo, repository, token, opts) do
      translate(repo, repository, token, number, :get, Common.pagination_fields(opts), opts)
    end
  end

  @spec reply_to_pr(repo_config(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reply_to_pr(repo, repository, token, opts) do
    with {:ok, comment_id} <- Common.required_comment_id(opts),
         {:ok, body} <- Common.required_reply_body(opts) do
      with {:ok, number} <- Common.resolve_pull_number(repo, repository, token, opts) do
        translate(
          repo,
          repository,
          token,
          number,
          :post,
          %{"body" => body, "in_reply_to" => comment_id},
          opts
        )
      end
    end
  end

  @spec translate(repo_config(), String.t(), String.t(), term(), atom(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def translate(repo, repository, token, number, :get, fields, opts) do
    with {:ok, comments} <- list_all(repo, repository, token, number, opts),
         {:ok, comments} <- Common.maybe_slice(comments, fields) do
      {:ok, Enum.map(comments, &Normalizer.normalize_review_comment/1)}
    end
  end

  def translate(repo, repository, token, number, :post, fields, opts) do
    with {:ok, body} <- Common.required_field(fields, "body"),
         {:ok, reply_to} <- Common.required_field(fields, "in_reply_to"),
         {:ok, comment} <- find(repo, repository, token, number, reply_to, opts),
         {:ok, review_id} <- Normalizer.review_comment_review_id(comment, reply_to),
         {:ok, payload} <-
           HttpClient.request_repo_payload(
             repo,
             repository,
             token,
             :post,
             "/-/pulls/#{number}/reviews/#{review_id}/replies",
             %{},
             %{"body" => body, "reply_to_comment_id" => to_string(reply_to)},
             opts
           ),
         {:ok, reply} <- Normalizer.expect_map(payload, :review_comment_reply) do
      {:ok, Normalizer.normalize_review_comment(reply)}
    end
  end

  def translate(_repo, _repository, _token, _number, method, _fields, _opts) do
    {:error, Error.invalid_invocation("Unsupported CNB review comment method: #{Common.method_name(method)}")}
  end

  @spec list_all(repo_config(), String.t(), String.t(), term(), keyword()) :: {:ok, list()} | {:error, term()}
  def list_all(repo, repository, token, number, opts) do
    with {:ok, reviews} <- Reviews.list_all(repo, repository, token, number, opts),
         review_ids <- Enum.flat_map(reviews, &Normalizer.review_id_values/1),
         {:ok, comments} <-
           list_review_comments(repo, repository, token, number, review_ids, opts) do
      {:ok,
       Enum.sort_by(comments, fn comment ->
         {to_string(Normalizer.field_value(comment, "created_at", :created_at) || ""), to_string(Normalizer.field_value(comment, "id", :id) || "")}
       end)}
    end
  end

  @spec find(repo_config(), String.t(), String.t(), term(), term(), keyword()) :: {:ok, map()} | {:error, Error.t() | term()}
  def find(repo, repository, token, number, comment_id, opts) do
    with {:ok, comments} <- list_all(repo, repository, token, number, opts) do
      case Enum.find(comments, &(to_string(Normalizer.field_value(&1, "id", :id)) == to_string(comment_id))) do
        nil ->
          {:error,
           Error.runtime_failure(
             :cnb_review_comment_not_found,
             "Unable to find CNB review comment #{comment_id}"
           )}

        comment ->
          {:ok, comment}
      end
    end
  end

  defp list_review_comments(_repo, _repository, _token, _number, [], _opts), do: {:ok, []}

  defp list_review_comments(repo, repository, token, number, review_ids, opts) do
    Enum.reduce_while(review_ids, {:ok, []}, fn review_id, {:ok, acc} ->
      case list_review_comments_for_review(repo, repository, token, number, review_id, opts) do
        {:ok, comments} -> {:cont, {:ok, acc ++ comments}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp list_review_comments_for_review(repo, repository, token, number, review_id, opts) do
    Common.fetch_pages([], 1, fn page ->
      with {:ok, payload} <-
             HttpClient.request_repo_payload(
               repo,
               repository,
               token,
               :get,
               "/-/pulls/#{number}/reviews/#{review_id}/comments",
               %{"page" => page, "page_size" => 100},
               nil,
               opts
             ),
           {:ok, comments} <- Normalizer.expect_list(payload, :review_comments) do
        {:ok, comments, length(comments) == 100}
      end
    end)
  end
end
