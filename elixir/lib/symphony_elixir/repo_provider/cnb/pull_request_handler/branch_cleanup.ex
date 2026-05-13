defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler.BranchCleanup do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler.Common

  @type repo_config :: map()

  @spec close_open_pull_requests_for_branch(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def close_open_pull_requests_for_branch(repo, repository, token, branch, opts) do
    with {:ok, pulls} <- list_open_pull_requests(repo, repository, token, branch, opts) do
      {errors, closed_count} =
        Enum.reduce(pulls, {[], 0}, fn pull, {errors, closed_count} ->
          number = Normalizer.pull_number(pull)

          case close_single_pull_request(repo, repository, token, number, opts) do
            :ok -> {errors, closed_count + 1}
            {:error, reason} -> {[reason | errors], closed_count}
          end
        end)

      maybe_log_close_summary(branch, closed_count, errors, opts)

      case Enum.reverse(errors) do
        [] -> :ok
        [reason | _rest] -> {:error, reason}
      end
    end
  end

  @spec list_open_pull_requests(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def list_open_pull_requests(repo, repository, token, branch, opts) do
    requester = HttpClient.requester(opts)
    api_base_url = HttpClient.api_base_url(repo)
    branch_filter = branch_head_ref(branch, opts)

    Common.fetch_pages([], 1, fn page ->
      path =
        "#{api_base_url}/#{URI.encode(repository, &URI.char_unreserved?/1)}/-/pulls?page=#{page}&page_size=100&state=open&order_by=-updated_at"

      case HttpClient.request_json(repo, requester, :get, path, token, nil) do
        {:ok, _status, pulls} when is_list(pulls) ->
          matching =
            Enum.filter(pulls, fn pull ->
              pull
              |> Normalizer.pull_head_ref()
              |> branch_matches?(branch_filter)
            end)

          {:ok, matching, length(pulls) == 100}

        {:ok, _status, payload} ->
          {:error, {:cnb_unknown_payload, :list_pulls, payload}}

        {:error, _reason} = error ->
          error
      end
    end)
  end

  defp close_single_pull_request(_repo, _repository, _token, nil, _opts),
    do: {:error, {:cnb_unknown_payload, :missing_pull_number}}

  defp close_single_pull_request(repo, repository, token, number, opts) do
    requester = HttpClient.requester(opts)
    api_base_url = HttpClient.api_base_url(repo)
    url = "#{api_base_url}/#{URI.encode(repository, &URI.char_unreserved?/1)}/-/pulls/#{number}"

    case HttpClient.request_json(repo, requester, :patch, url, token, %{state: "closed"}) do
      {:ok, status, _payload} when status in 200..299 ->
        :ok

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :close_pull, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_log_close_summary(_branch, _closed_count, [], _opts), do: :ok

  defp maybe_log_close_summary(branch, closed_count, errors, opts) do
    info = Keyword.get(opts, :info, fn message -> Mix.shell().info(message) end)
    error = Keyword.get(opts, :error, fn message -> Mix.shell().error(message) end)

    if closed_count > 0 do
      info.("Closed #{closed_count} CNB PR(s) for branch #{branch}")
    end

    Enum.each(errors, fn reason ->
      error.("Failed to close CNB PRs for branch #{branch}: #{inspect(reason)}")
    end)
  end

  defp branch_head_ref(branch, opts), do: opts[:branch_head_ref] || "refs/heads/#{branch}"

  defp branch_matches?(nil, _branch_filter), do: false
  defp branch_matches?(_head_ref, ""), do: false

  defp branch_matches?(head_ref, branch_filter)
       when is_binary(head_ref) and is_binary(branch_filter) do
    head_ref == branch_filter or String.ends_with?(head_ref, "/#{branch_name(branch_filter)}")
  end

  defp branch_name("refs/heads/" <> branch), do: branch
  defp branch_name(branch), do: branch
end
