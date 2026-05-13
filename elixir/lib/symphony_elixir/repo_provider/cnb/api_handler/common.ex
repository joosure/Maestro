defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.Common do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler
  alias SymphonyElixir.RepoProvider.Error

  @type repo_config :: map()

  @spec require_api_endpoint(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def require_api_endpoint(opts) do
    case Keyword.get(opts, :endpoint) do
      endpoint when is_binary(endpoint) and endpoint != "" -> {:ok, endpoint}
      _other -> {:error, Error.invalid_invocation("CNB api requires an endpoint")}
    end
  end

  @spec api_method(keyword()) :: {:ok, atom()} | {:error, Error.t()}
  def api_method(opts) do
    raw_method =
      opts
      |> Keyword.get(:method, "GET")
      |> to_string()
      |> String.upcase()

    case raw_method do
      "GET" -> {:ok, :get}
      "POST" -> {:ok, :post}
      "PUT" -> {:ok, :put}
      "PATCH" -> {:ok, :patch}
      "DELETE" -> {:ok, :delete}
      _other -> {:error, Error.invalid_invocation("Unsupported CNB api method: #{raw_method}")}
    end
  end

  @spec normalize_api_fields(term()) :: map()
  def normalize_api_fields(fields) when is_map(fields), do: fields
  def normalize_api_fields(_fields), do: %{}

  @spec translate_query_fields(map()) :: map()
  def translate_query_fields(fields) do
    Enum.reduce(fields, %{}, fn {key, value}, acc ->
      case to_string(key) do
        "per_page" -> Map.put(acc, "page_size", value)
        "page" -> Map.put(acc, "page", value)
        "sort" -> Map.put(acc, "sort", value)
        _other -> acc
      end
    end)
  end

  @spec resolve_pull_number(repo_config(), String.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def resolve_pull_number(repo, repository, token, opts) do
    pull_lookup =
      case opts[:number] do
        number when is_binary(number) and number != "" ->
          PullRequestHandler.resolve_pull_for_mutation(repo, repository, token, opts)

        _other ->
          PullRequestHandler.resolve_pull(repo, repository, token, opts)
      end

    with {:ok, pull} <- pull_lookup do
      require_pull_number(pull, :review_comments_pull)
    end
  end

  @spec require_pull_number(map(), atom()) :: {:ok, term()} | {:error, term()}
  def require_pull_number(pull, action) do
    case Normalizer.pull_number(pull) do
      nil -> {:error, {:cnb_unknown_payload, action, pull}}
      "" -> {:error, {:cnb_unknown_payload, action, pull}}
      number -> {:ok, number}
    end
  end

  @spec pagination_fields(keyword()) :: map()
  def pagination_fields(opts) do
    %{}
    |> maybe_put_query_field("page", opts[:page])
    |> maybe_put_query_field("per_page", opts[:per_page])
  end

  @spec maybe_slice(list(), map()) :: {:ok, list()} | {:error, Error.t()}
  def maybe_slice(items, fields) when is_list(items) and is_map(fields) do
    if pagination_requested?(fields) do
      with {:ok, {page, per_page}} <- pagination_values(fields) do
        {:ok, Normalizer.slice_page(items, page, per_page)}
      end
    else
      {:ok, items}
    end
  end

  @spec pagination_values(map()) :: {:ok, {pos_integer(), pos_integer()}} | {:error, Error.t()}
  def pagination_values(fields) do
    with {:ok, page} <- positive_integer_field(fields, "page", :page, 1),
         {:ok, per_page} <- positive_integer_field(fields, "per_page", :per_page, 100) do
      {:ok, {page, per_page}}
    end
  end

  @spec required_comment_id(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def required_comment_id(opts) do
    case opts[:comment_id] do
      comment_id when is_binary(comment_id) and comment_id != "" ->
        {:ok, comment_id}

      comment_id when is_integer(comment_id) ->
        {:ok, Integer.to_string(comment_id)}

      _other ->
        {:error, Error.invalid_invocation("CNB pr-reply-review-comment requires a comment id")}
    end
  end

  @spec required_reply_body(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def required_reply_body(opts) do
    case opts[:body] do
      body when is_binary(body) and body != "" ->
        {:ok, body}

      _other ->
        {:error, Error.invalid_invocation("CNB pr-reply-review-comment requires a non-empty body")}
    end
  end

  @spec required_issue_comment_body(keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def required_issue_comment_body(opts) do
    case opts[:body] do
      body when is_binary(body) and body != "" ->
        {:ok, body}

      _other ->
        {:error, Error.invalid_invocation("CNB pr-add-issue-comment requires a non-empty body")}
    end
  end

  @spec required_field(map(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def required_field(fields, key) do
    case Normalizer.field_value(fields, key, api_field_atom(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value when not is_nil(value) and value != "" -> {:ok, to_string(value)}
      _other -> {:error, Error.invalid_invocation("CNB api requires field #{key}")}
    end
  end

  @spec maybe_put_work_mode(map(), map()) :: map()
  def maybe_put_work_mode(body, fields) do
    case Normalizer.field_value(fields, "work_mode", :work_mode) do
      nil -> body
      value -> Map.put(body, "work_mode", truthy_value(value))
    end
  end

  @spec method_name(atom()) :: String.t()
  def method_name(method) when is_atom(method) do
    method
    |> Atom.to_string()
    |> String.upcase()
  end

  @spec fetch_pages(list(), pos_integer(), function()) :: {:ok, list()} | {:error, term()}
  def fetch_pages(acc, page, fetcher) do
    case fetcher.(page) do
      {:ok, items, true} -> fetch_pages(acc ++ items, page + 1, fetcher)
      {:ok, items, false} -> {:ok, acc ++ items}
      {:error, _reason} = error -> error
    end
  end

  defp maybe_put_query_field(fields, _key, nil), do: fields
  defp maybe_put_query_field(fields, _key, ""), do: fields
  defp maybe_put_query_field(fields, key, value), do: Map.put(fields, key, value)

  defp pagination_requested?(fields) do
    not is_nil(Normalizer.field_value(fields, "page", :page)) or
      not is_nil(Normalizer.field_value(fields, "per_page", :per_page))
  end

  defp positive_integer_field(fields, key, atom_key, default) do
    case Normalizer.field_value(fields, key, atom_key) do
      nil ->
        {:ok, default}

      value ->
        case Integer.parse(to_string(value)) do
          {integer, ""} when integer > 0 ->
            {:ok, integer}

          _other ->
            {:error, Error.invalid_invocation("Invalid CNB api #{key}: #{value}")}
        end
    end
  end

  defp api_field_atom("body"), do: :body
  defp api_field_atom("in_reply_to"), do: :in_reply_to
  defp api_field_atom("work_mode"), do: :work_mode
  defp api_field_atom("page"), do: :page
  defp api_field_atom("per_page"), do: :per_page
  defp api_field_atom("sort"), do: :sort
  defp api_field_atom(_key), do: :unknown

  defp truthy_value(value) do
    value
    |> to_string()
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))
  end
end
