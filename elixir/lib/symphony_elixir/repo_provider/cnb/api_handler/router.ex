defmodule SymphonyElixir.RepoProvider.CNB.ApiHandler.Router do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.CNB.ApiHandler.{CheckRuns, Common, IssueComments, ReviewComments, Reviews}
  alias SymphonyElixir.RepoProvider.CNB.HttpClient
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig

  @translated_repo_endpoint_markers ~w(issues pulls commits)

  @type repo_config :: map()

  @spec api(repo_config(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def api(repo, token, opts) do
    with {:ok, endpoint} <- Common.require_api_endpoint(opts),
         {:ok, method} <- Common.api_method(opts),
         fields <- Keyword.get(opts, :fields, %{}),
         {:ok, payload} <- dispatch_api(repo, token, endpoint, method, fields, opts) do
      {:ok, payload}
    end
  end

  defp dispatch_api(repo, token, endpoint, method, fields, opts) do
    fields = Common.normalize_api_fields(fields)

    with {:ok, split_endpoint} <- split_repo_endpoint(repo, endpoint, opts) do
      case split_endpoint do
        {repository, tail} when is_binary(repository) and is_binary(tail) ->
          case String.split(tail, "/", trim: true) do
            ["issues", number, "comments"] ->
              IssueComments.translate(repo, repository, token, number, method, fields, opts)

            ["pulls", number, "reviews"] ->
              Reviews.translate(repo, repository, token, number, method, fields, opts)

            ["pulls", number, "comments"] ->
              ReviewComments.translate(repo, repository, token, number, method, fields, opts)

            ["commits", sha, "check-runs"] ->
              CheckRuns.translate(repo, repository, token, sha, method, fields, opts)

            _other ->
              direct_api(repo, token, method, endpoint, fields, opts)
          end

        _other ->
          direct_api(repo, token, method, endpoint, fields, opts)
      end
    end
  end

  defp direct_api(repo, token, method, endpoint, fields, opts) do
    query = if method == :get, do: Common.translate_query_fields(fields), else: %{}
    body = if method == :get or map_size(fields) == 0, do: nil, else: fields
    HttpClient.request_api_payload(repo, token, method, endpoint, query, body, opts)
  end

  defp split_repo_endpoint(repo, "repos/{owner}/{repo}/" <> tail, opts) do
    with {:ok, repository} <- resolve_repository(repo, opts) do
      {:ok, {repository, tail}}
    end
  end

  defp split_repo_endpoint(_repo, "repos/" <> rest, _opts) do
    segments = String.split(rest, "/", trim: true)

    case Enum.find_index(segments, &(&1 in @translated_repo_endpoint_markers)) do
      index when is_integer(index) and index > 0 ->
        {repository_segments, tail_segments} = Enum.split(segments, index)
        {:ok, {Enum.join(repository_segments, "/"), Enum.join(tail_segments, "/")}}

      _other ->
        {:ok, {nil, nil}}
    end
  end

  defp split_repo_endpoint(_repo, _endpoint, _opts), do: {:ok, {nil, nil}}

  defp resolve_repository(repo, opts) do
    case opts[:repo] || RepoConfig.repository(repo) do
      repository when is_binary(repository) and repository != "" ->
        {:ok, repository}

      _other ->
        {:error, :missing_cnb_repository_slug}
    end
  end
end
