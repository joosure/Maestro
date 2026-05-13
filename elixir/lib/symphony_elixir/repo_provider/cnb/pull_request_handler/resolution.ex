defmodule SymphonyElixir.RepoProvider.CNB.PullRequestHandler.Resolution do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.CNB.Normalizer
  alias SymphonyElixir.RepoProvider.CNB.PullRequestHandler.{BranchCleanup, Common}

  @type repo_config :: map()
  @pull_url_marker ["-", "pulls"]

  @spec resolve_pull(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_pull(repo, repository, token, opts) do
    resolve_pull_target(
      opts,
      fn target ->
        resolve_explicit_pull_target(repo, repository, token, target, opts)
      end,
      fn ->
        resolve_current_branch_pull(repo, repository, token, opts)
      end
    )
  end

  @spec resolve_pull_for_mutation(repo_config(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_pull_for_mutation(repo, repository, token, opts) do
    resolve_pull_target(
      opts,
      fn target ->
        resolve_explicit_pull_target(repo, repository, token, target, opts)
      end,
      fn ->
        resolve_current_branch_pull_for_mutation(repo, repository, token, opts)
      end
    )
  end

  @spec resolve_pull_by_sha(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_pull_by_sha(repo, repository, token, sha, opts) do
    with {:ok, pulls} <- list_pull_requests(repo, repository, token, "all", opts) do
      pulls
      |> Enum.filter(&(Normalizer.pull_head_sha(&1) == sha))
      |> Enum.sort_by(&Normalizer.pull_state_priority/1)
      |> case do
        [pull | _rest] -> {:ok, pull}
        [] -> {:error, {:cnb_pull_not_found_for_sha, sha}}
      end
    end
  end

  @spec resolve_pull_for_branch(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_pull_for_branch(repo, repository, token, branch, opts) do
    with {:ok, pulls} <- list_pull_requests(repo, repository, token, "all", opts) do
      matching =
        Enum.filter(pulls, fn pull ->
          Normalizer.pull_head_branch(pull) == branch
        end)

      case matching do
        [pull | _rest] -> {:ok, pull}
        [] -> {:error, {:cnb_pull_not_found, branch}}
      end
    end
  end

  @spec list_pull_requests(repo_config(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def list_pull_requests(repo, repository, token, state, opts) do
    requester = HttpClient.requester(opts)

    Common.fetch_pages([], 1, fn page ->
      url =
        HttpClient.repo_url(repo, repository, "/-/pulls", %{
          "page" => page,
          "page_size" => 100,
          "state" => state,
          "order_by" => "-updated_at"
        })

      case HttpClient.request_json(repo, requester, :get, url, token, nil) do
        {:ok, _status, payload} when is_list(payload) ->
          {:ok, payload, length(payload) == 100}

        {:ok, _status, payload} ->
          {:error, {:cnb_unknown_payload, :list_pulls, payload}}

        {:error, _reason} = error ->
          error
      end
    end)
  end

  defp resolve_explicit_pull_target(repo, repository, token, target, opts) do
    case normalize_pull_target(repository, target) do
      {:ok, {:number, number}} -> fetch_pull(repo, repository, token, number, opts)
      {:ok, {:branch, branch}} -> resolve_pull_for_branch(repo, repository, token, branch, opts)
      {:error, _reason} = error -> error
    end
  end

  defp resolve_pull_target(opts, explicit_fun, current_fun) do
    case Keyword.fetch(opts, :number) do
      {:ok, nil} ->
        current_fun.()

      {:ok, target} when is_binary(target) ->
        if String.trim(target) == "" do
          current_fun.()
        else
          explicit_fun.(target)
        end

      {:ok, target} ->
        explicit_fun.(target)

      :error ->
        current_fun.()
    end
  end

  defp fetch_pull(repo, repository, token, number, opts) do
    requester = HttpClient.requester(opts)

    url =
      "#{HttpClient.api_base_url(repo)}/#{URI.encode(repository, &URI.char_unreserved?/1)}/-/pulls/#{number}"

    case HttpClient.request_json(repo, requester, :get, url, token, nil) do
      {:ok, _status, payload} when is_map(payload) ->
        {:ok, payload}

      {:ok, _status, payload} ->
        {:error, {:cnb_unknown_payload, :fetch_pull, payload}}

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize_pull_target(repository, target) when is_binary(target) do
    target = String.trim(target)

    cond do
      target == "" ->
        {:error, {:cnb_invalid_pull_target, target}}

      pull_number?(target) ->
        {:ok, {:number, target}}

      String.starts_with?(target, ["http://", "https://"]) ->
        normalize_pull_url_target(repository, target)

      true ->
        {:ok, {:branch, target}}
    end
  end

  defp normalize_pull_target(_repository, target) when is_integer(target), do: {:ok, {:number, Integer.to_string(target)}}
  defp normalize_pull_target(_repository, target), do: {:error, {:cnb_invalid_pull_target, target}}

  defp normalize_pull_url_target(repository, target) do
    with {:ok, url_repository, number} <- parse_pull_url(target),
         :ok <- validate_pull_url_repository(repository, url_repository, target) do
      {:ok, {:number, number}}
    end
  end

  defp parse_pull_url(target) do
    target
    |> URI.parse()
    |> case do
      %URI{path: path} when is_binary(path) ->
        parse_pull_url_path(path)

      _uri ->
        {:error, {:cnb_invalid_pull_target, target}}
    end
  end

  defp parse_pull_url_path(path) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&URI.decode/1)

    case split_pull_url_segments(segments) do
      {repository_segments, [number | _rest]} when repository_segments != [] and number != "" ->
        {:ok, Enum.join(repository_segments, "/"), number}

      _other ->
        {:error, {:cnb_invalid_pull_target, path}}
    end
  end

  defp split_pull_url_segments(segments) do
    case Enum.split_while(segments, &(&1 != "-")) do
      {repository_segments, @pull_url_marker ++ pull_segments} -> {repository_segments, pull_segments}
      _other -> {[], []}
    end
  end

  defp validate_pull_url_repository(expected, actual, _target) when expected == actual, do: :ok

  defp validate_pull_url_repository(expected, actual, target) do
    {:error, {:cnb_pull_target_repository_mismatch, target, expected, actual}}
  end

  defp pull_number?(target), do: String.match?(target, ~r/^\d+$/)

  defp resolve_current_branch_pull(repo, repository, token, opts) do
    branch =
      Keyword.get(opts, :branch) ||
        Common.current_branch(repo, opts)

    if is_binary(branch) and branch != "" do
      with {:ok, pulls} <- BranchCleanup.list_open_pull_requests(repo, repository, token, branch, opts) do
        case pulls do
          [pull | _rest] -> {:ok, pull}
          [] -> {:error, {:cnb_pull_not_found, branch}}
        end
      end
    else
      {:error, :cnb_current_branch_unavailable}
    end
  end

  defp resolve_current_branch_pull_for_mutation(repo, repository, token, opts) do
    with {:ok, branch} <- Common.require_current_branch(repo, opts),
         {:ok, pulls} <- list_pull_requests(repo, repository, token, "all", opts) do
      pulls
      |> Enum.filter(&(Normalizer.pull_head_branch(&1) == branch))
      |> Enum.sort_by(&Normalizer.pull_state_priority/1)
      |> case do
        [pull | _rest] -> {:ok, pull}
        [] -> {:error, {:cnb_pull_not_found_for_branch, branch}}
      end
    end
  end
end
