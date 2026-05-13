defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler.Mutations do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler.{Common, Resolution}
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec pr_create(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def pr_create(repo, repository, token, opts) do
    with {:ok, title} <- require_title(opts),
         {:ok, head} <- resolve_create_head(repo, opts),
         {:ok, pull} <-
           create_pull_request(
             repo,
             repository,
             token,
             %{
               "title" => title,
               "body" => Keyword.get(opts, :body, ""),
               "base" => Common.first_present(Keyword.get(opts, :base), Common.base_branch(repo, opts)),
               "head" => head
             },
             opts
           ),
         {:ok, number} <- Common.require_pull_number(pull, :create_pull) do
      {:ok, HttpClient.pr_url(repo, repository, number)}
    end
  end

  @spec pr_edit(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def pr_edit(repo, repository, token, opts) do
    with {:ok, pull} <- Resolution.resolve_pull_for_mutation(repo, repository, token, opts),
         {:ok, body} <- pr_edit_body(opts),
         {:ok, _payload} <-
           update_pull_request(repo, repository, token, Normalizer.pull_number(pull), body, opts),
         {:ok, number} <- Common.require_pull_number(pull, :edit_pull) do
      {:ok, HttpClient.pr_url(repo, repository, number)}
    end
  end

  @spec pr_close(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def pr_close(repo, repository, token, opts) do
    with {:ok, pull} <- Resolution.resolve_pull_for_mutation(repo, repository, token, opts),
         {:ok, number} <- Common.require_pull_number(pull, :close_pull),
         {:ok, _payload} <-
           update_pull_request(repo, repository, token, number, %{"state" => "closed"}, opts) do
      {:ok, HttpClient.pr_url(repo, repository, number)}
    end
  end

  @spec pr_merge(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def pr_merge(repo, repository, token, opts) do
    with {:ok, pull} <- Resolution.resolve_pull_for_mutation(repo, repository, token, opts),
         {:ok, number} <- Common.require_pull_number(pull, :merge_pull),
         {:ok, _payload} <-
           merge_pull_request(repo, repository, token, number, merge_body(pull, opts), opts) do
      {:ok, HttpClient.pr_url(repo, repository, number)}
    end
  end

  defp create_pull_request(repo, repository, token, body, opts) do
    requester = HttpClient.requester(opts)
    url = HttpClient.repo_url(repo, repository, "/-/pulls", %{})

    case HttpClient.request_json(repo, requester, :post, url, token, body) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :create_pull, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  defp update_pull_request(_repo, _repository, _token, nil, _body, _opts),
    do: {:error, {:cnb_unknown_payload, :missing_pull_number, nil}}

  defp update_pull_request(repo, repository, token, number, body, opts) do
    requester = HttpClient.requester(opts)
    url = HttpClient.repo_url(repo, repository, "/-/pulls/#{number}", %{})

    case HttpClient.request_json(repo, requester, :patch, url, token, body) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :update_pull, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  defp merge_pull_request(repo, repository, token, number, body, opts) do
    requester = HttpClient.requester(opts)
    url = HttpClient.repo_url(repo, repository, "/-/pulls/#{number}/merge", %{})

    case HttpClient.request_json(repo, requester, :put, url, token, body) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :merge_pull, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  defp require_title(opts) do
    case Keyword.get(opts, :title) do
      title when is_binary(title) and title != "" ->
        {:ok, title}

      _other ->
        {:error, Error.invalid_invocation("CNB pr-create requires --title")}
    end
  end

  defp resolve_create_head(repo, opts) do
    case Keyword.get(opts, :head) do
      head when is_binary(head) and head != "" -> {:ok, head}
      _other -> Common.require_current_branch(repo, opts)
    end
  end

  defp pr_edit_body(opts) do
    body =
      []
      |> maybe_put_body_field("title", opts, :title)
      |> maybe_put_body_field("body", opts, :body)
      |> Map.new()

    if map_size(body) == 0 do
      {:error, Error.invalid_invocation("CNB pr-edit requires at least one editable field")}
    else
      {:ok, body}
    end
  end

  defp maybe_put_body_field(fields, field, opts, key) do
    if Keyword.has_key?(opts, key) do
      [{field, Keyword.get(opts, key)} | fields]
    else
      fields
    end
  end

  defp merge_body(pull, opts) do
    %{
      "merge_style" => Keyword.get(opts, :merge_style, "merge"),
      "commit_title" => Common.first_present(Keyword.get(opts, :subject), Normalizer.pull_title(pull)),
      "commit_message" => Common.first_present(Keyword.get(opts, :body), Normalizer.pull_body(pull))
    }
  end
end
