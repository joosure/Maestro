defmodule SymphonyElixir.RepoProvider.GitHub.ApiHandler do
  @moduledoc """
  API proxy operations for the GitHub adapter.

  Handles generic GitHub REST API calls with endpoint template
  expansion. Called by `GitHub.Adapter` for the `api/2` callback.
  """

  alias SymphonyElixir.RepoProvider.CommandNames
  alias SymphonyElixir.RepoProvider.Error
  alias SymphonyElixir.RepoProvider.GitHub.CLI
  alias SymphonyElixir.RepoProvider.GitHub.Normalizer

  @type repo_config :: map()
  @default_comments_per_page 100
  @api_command CommandNames.api()
  @pr_issue_comments_command CommandNames.pr_issue_comments()
  @pr_reviews_command CommandNames.pr_reviews()
  @pr_review_comments_command CommandNames.pr_review_comments()

  # ── Public API ───────────────────────────────────────────────────

  @spec api(repo_config(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def api(repo, opts) do
    with {:ok, endpoint} <- expand_api_endpoint(opts[:endpoint], repo, opts) do
      args =
        [@api_command, endpoint, "--method", opts[:method] || "GET"]
        |> append_api_fields(opts[:fields] || %{})

      case CLI.run_command("gh", args, opts) do
        {:ok, output} ->
          CLI.decode_json_output(
            output,
            :github_invalid_payload,
            "Failed to decode GitHub API payload"
          )

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_api_failed, String.trim(output))}
      end
    end
  end

  @spec pr_issue_comments(repo_config(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def pr_issue_comments(repo, opts) do
    with {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, comments} <-
           list_comments(
             repo,
             @pr_issue_comments_command,
             "repos/{owner}/{repo}/issues/#{number}/comments",
             opts
           ) do
      {:ok, Enum.map(comments, &Normalizer.normalize_issue_comment/1)}
    end
  end

  @spec pr_add_issue_comment(repo_config(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pr_add_issue_comment(repo, opts) do
    with {:ok, body} <-
           require_body(opts, "GitHub pr-add-issue-comment requires a non-empty body"),
         {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, payload} <-
           api(
             repo,
             Keyword.merge(opts,
               endpoint: "repos/{owner}/{repo}/issues/#{number}/comments",
               method: "POST",
               fields: %{"body" => body}
             )
           ) do
      case payload do
        comment when is_map(comment) ->
          {:ok, Normalizer.normalize_issue_comment(comment)}

        _other ->
          {:error,
           Error.runtime_failure(
             :github_invalid_payload,
             "Unexpected GitHub issue comment payload",
             payload
           )}
      end
    end
  end

  @spec pr_reviews(repo_config(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def pr_reviews(repo, opts) do
    with {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, reviews} <-
           list_reviews(
             repo,
             @pr_reviews_command,
             "repos/{owner}/{repo}/pulls/#{number}/reviews",
             opts
           ) do
      {:ok, Enum.map(reviews, &Normalizer.normalize_review/1)}
    end
  end

  @spec pr_submit_review(repo_config(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pr_submit_review(repo, opts) do
    with {:ok, event} <- review_event(opts),
         {:ok, body} <- require_body(opts, "GitHub pr-submit-review requires a non-empty body"),
         {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, payload} <-
           api(
             repo,
             Keyword.merge(opts,
               endpoint: "repos/{owner}/{repo}/pulls/#{number}/reviews",
               method: "POST",
               fields: %{"body" => body, "event" => event}
             )
           ) do
      case payload do
        review when is_map(review) ->
          {:ok, Normalizer.normalize_review(review)}

        _other ->
          {:error,
           Error.runtime_failure(
             :github_invalid_payload,
             "Unexpected GitHub review payload",
             payload
           )}
      end
    end
  end

  @spec pr_review_comments(repo_config(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def pr_review_comments(repo, opts) do
    with {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, comments} <-
           list_comments(
             repo,
             @pr_review_comments_command,
             "repos/{owner}/{repo}/pulls/#{number}/comments",
             opts
           ) do
      {:ok, Enum.map(comments, &Normalizer.normalize_review_comment/1)}
    end
  end

  @spec pr_reply_review_comment(repo_config(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def pr_reply_review_comment(repo, opts) do
    with {:ok, comment_id} <- require_comment_id(opts),
         {:ok, body} <- require_reply_body(opts),
         {:ok, number} <- resolve_pull_number(repo, opts),
         {:ok, payload} <-
           api(
             repo,
             Keyword.merge(opts,
               endpoint: "repos/{owner}/{repo}/pulls/#{number}/comments",
               method: "POST",
               fields: %{"body" => body, "in_reply_to" => comment_id}
             )
           ) do
      case payload do
        reply when is_map(reply) ->
          {:ok, Normalizer.normalize_review_comment(reply)}

        _other ->
          {:error,
           Error.runtime_failure(
             :github_invalid_payload,
             "Unexpected GitHub review comment reply payload",
             payload
           )}
      end
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp expand_api_endpoint(nil, _repo, _opts), do: {:ok, nil}

  defp expand_api_endpoint(endpoint, repo, opts) when is_binary(endpoint) do
    if String.contains?(endpoint, "{owner}") or String.contains?(endpoint, "{repo}") do
      with {:ok, repository} <- CLI.require_repository(repo, opts) do
        case String.split(repository, "/", parts: 2) do
          [owner, repo_name] ->
            {:ok,
             endpoint
             |> String.replace("{owner}", owner)
             |> String.replace("{repo}", repo_name)}

          _other ->
            {:ok, endpoint}
        end
      end
    else
      {:ok, endpoint}
    end
  end

  defp append_api_fields(args, fields) when is_map(fields) do
    fields
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.reduce(args, fn {key, value}, acc ->
      acc ++ ["-F", "#{key}=#{value}"]
    end)
  end

  defp append_api_fields(args, _fields), do: args

  defp resolve_pull_number(repo, opts) do
    case opts[:number] do
      number when is_binary(number) and number != "" ->
        normalize_pull_number(repo, String.trim(number), opts)

      _other ->
        resolve_current_pull_number(repo, opts)
    end
  end

  defp normalize_pull_number(repo, target, opts) do
    if pull_url?(target) do
      pull_number_from_url(repo, target, opts)
    else
      {:ok, target}
    end
  end

  defp pull_url?(target) when is_binary(target),
    do: String.starts_with?(target, ["http://", "https://"])

  defp pull_number_from_url(repo, target, opts) do
    with {:ok, url_repository, number} <- parse_pull_url(target),
         {:ok, repository} <- CLI.require_repository(repo, opts),
         :ok <- validate_pull_url_repository(repository, url_repository, target) do
      {:ok, number}
    end
  end

  defp parse_pull_url(target) do
    target
    |> URI.parse()
    |> case do
      %URI{path: path} when is_binary(path) ->
        parse_pull_url_path(path)

      _uri ->
        {:error, Error.invalid_invocation("GitHub PR URL must include /owner/repo/pull/number")}
    end
  end

  defp parse_pull_url_path(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&URI.decode/1)

    case segments do
      [owner, repo, "pull", number | _rest] when owner != "" and repo != "" and number != "" ->
        {:ok, "#{owner}/#{repo}", number}

      _other ->
        {:error, Error.invalid_invocation("GitHub PR URL must include /owner/repo/pull/number")}
    end
  end

  defp validate_pull_url_repository(expected, actual, _target) do
    if String.downcase(expected) == String.downcase(actual) do
      :ok
    else
      {:error, Error.invalid_invocation("GitHub PR URL repository #{actual} does not match configured repository #{expected}")}
    end
  end

  defp review_event(opts) do
    case opts[:event] do
      event when is_binary(event) ->
        event
        |> String.trim()
        |> String.downcase()
        |> String.replace(~r/[\s-]+/, "_")
        |> case do
          "comment" ->
            {:ok, "COMMENT"}

          "approve" ->
            {:ok, "APPROVE"}

          "approved" ->
            {:ok, "APPROVE"}

          "request_changes" ->
            {:ok, "REQUEST_CHANGES"}

          "change_request" ->
            {:ok, "REQUEST_CHANGES"}

          "changes_requested" ->
            {:ok, "REQUEST_CHANGES"}

          _event ->
            {:error, Error.invalid_invocation("GitHub pr-submit-review event must be comment, approve, or request_changes")}
        end

      _event ->
        {:error, Error.invalid_invocation("GitHub pr-submit-review requires event")}
    end
  end

  defp resolve_current_pull_number(repo, opts) do
    with {:ok, repository} <- CLI.require_repository(repo, opts),
         {:ok, pr_target} <- CLI.resolve_pr_target(repo, opts) do
      case CLI.run_command(
             "gh",
             [
               "pr",
               "view",
               pr_target,
               "--repo",
               repository,
               "--json",
               "number",
               "--jq",
               ".number"
             ],
             opts
           ) do
        {:ok, output} ->
          case CLI.extract_scalar_output(output) do
            "" ->
              {:error,
               Error.runtime_failure(
                 :github_pr_view_failed,
                 "Unable to determine current GitHub PR number"
               )}

            number ->
              {:ok, number}
          end

        {:error, {:enoent, _output}} ->
          {:error, CLI.enoent_error()}

        {:error, {_status, output}} ->
          {:error, Error.runtime_failure(:github_pr_view_failed, String.trim(output))}
      end
    end
  end

  defp list_reviews(repo, command_name, endpoint, opts) do
    with {:ok, {page, per_page}} <- comment_pagination(opts, command_name) do
      if explicit_pagination?(opts) do
        fetch_reviews_page(repo, endpoint, page, per_page, opts)
      else
        fetch_all_reviews(repo, endpoint, page, per_page, [], opts)
      end
    end
  end

  defp fetch_all_reviews(repo, endpoint, page, per_page, acc, opts) do
    with {:ok, reviews} <- fetch_reviews_page(repo, endpoint, page, per_page, opts) do
      updated_acc = acc ++ reviews

      if length(reviews) == per_page do
        fetch_all_reviews(repo, endpoint, page + 1, per_page, updated_acc, opts)
      else
        {:ok, updated_acc}
      end
    end
  end

  defp fetch_reviews_page(repo, endpoint, page, per_page, opts) do
    with {:ok, payload} <-
           api(
             repo,
             Keyword.merge(opts,
               endpoint: endpoint,
               method: "GET",
               fields: %{"page" => page, "per_page" => per_page}
             )
           ) do
      case payload do
        reviews when is_list(reviews) ->
          {:ok, reviews}

        _other ->
          {:error,
           Error.runtime_failure(
             :github_invalid_payload,
             "Unexpected GitHub reviews payload",
             payload
           )}
      end
    end
  end

  defp list_comments(repo, command_name, endpoint, opts) do
    with {:ok, {page, per_page}} <- comment_pagination(opts, command_name) do
      if explicit_pagination?(opts) do
        fetch_comments_page(repo, endpoint, page, per_page, opts)
      else
        fetch_all_comments(repo, endpoint, page, per_page, [], opts)
      end
    end
  end

  defp fetch_all_comments(repo, endpoint, page, per_page, acc, opts) do
    with {:ok, comments} <- fetch_comments_page(repo, endpoint, page, per_page, opts) do
      updated_acc = acc ++ comments

      if length(comments) == per_page do
        fetch_all_comments(repo, endpoint, page + 1, per_page, updated_acc, opts)
      else
        {:ok, updated_acc}
      end
    end
  end

  defp fetch_comments_page(repo, endpoint, page, per_page, opts) do
    with {:ok, payload} <-
           api(
             repo,
             Keyword.merge(opts,
               endpoint: endpoint,
               method: "GET",
               fields: %{"page" => page, "per_page" => per_page}
             )
           ) do
      case payload do
        comments when is_list(comments) ->
          {:ok, comments}

        _other ->
          {:error,
           Error.runtime_failure(
             :github_invalid_payload,
             "Unexpected GitHub comments payload",
             payload
           )}
      end
    end
  end

  defp comment_pagination(opts, command_name) do
    with {:ok, page} <- positive_integer_opt(opts, :page, 1),
         {:ok, per_page} <- positive_integer_opt(opts, :per_page, @default_comments_per_page) do
      {:ok, {page, per_page}}
    else
      {:error, {:invalid_positive_integer_opt, key, value}} ->
        {:error, Error.invalid_invocation("Invalid GitHub #{command_name} #{Atom.to_string(key)}: #{value}")}
    end
  end

  defp explicit_pagination?(opts) do
    present_value?(opts[:page]) or present_value?(opts[:per_page])
  end

  defp positive_integer_opt(opts, key, default) do
    case opts[key] do
      value when value in [nil, ""] ->
        {:ok, default}

      value ->
        case Integer.parse(to_string(value)) do
          {integer, ""} when integer > 0 ->
            {:ok, integer}

          _other ->
            {:error, {:invalid_positive_integer_opt, key, value}}
        end
    end
  end

  defp present_value?(value), do: not is_nil(value) and value != ""

  defp require_comment_id(opts) do
    case opts[:comment_id] do
      comment_id when is_binary(comment_id) and comment_id != "" ->
        {:ok, comment_id}

      comment_id when is_integer(comment_id) ->
        {:ok, Integer.to_string(comment_id)}

      _other ->
        {:error, Error.invalid_invocation("GitHub pr-reply-review-comment requires a comment id")}
    end
  end

  defp require_body(opts, message) do
    case opts[:body] do
      body when is_binary(body) and body != "" ->
        {:ok, body}

      _other ->
        {:error, Error.invalid_invocation(message)}
    end
  end

  defp require_reply_body(opts),
    do: require_body(opts, "GitHub pr-reply-review-comment requires a non-empty body")
end
