defmodule SymphonyElixir.RepoProvider.RuntimeEnv do
  @moduledoc false

  alias SymphonyElixir.Repo.RuntimeEnv, as: RepoRuntimeEnv

  @repo_path_env "SYMPHONY_REPO_PATH"
  @repo_remote_env "SYMPHONY_REPO_REMOTE"
  @repo_remote_url_env "SYMPHONY_REPO_REMOTE_URL"
  @source_repo_remote_url_env "SOURCE_REPO_URL"
  @provider_kind_env "SYMPHONY_REPO_PROVIDER_KIND"
  @source_provider_kind_env "SOURCE_REPO_PROVIDER_KIND"
  @provider_repository_env "SYMPHONY_REPO_PROVIDER_REPOSITORY"
  @source_provider_repository_env "SOURCE_REPO_PROVIDER_REPOSITORY"
  @provider_api_base_url_env "SYMPHONY_REPO_PROVIDER_API_BASE_URL"
  @provider_web_base_url_env "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL"
  @provider_http_timeout_seconds_env "SYMPHONY_REPO_PROVIDER_HTTP_TIMEOUT_SECONDS"
  @provider_max_http_retries_env "SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES"
  @provider_retry_backoff_seconds_env "SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS"
  @source_repo_base_branch_env "SOURCE_REPO_BASE_BRANCH"

  @spec repo_path_env() :: String.t()
  def repo_path_env, do: @repo_path_env

  @spec repo_remote_env() :: String.t()
  def repo_remote_env, do: @repo_remote_env

  @spec repo_remote_url_env() :: String.t()
  def repo_remote_url_env, do: @repo_remote_url_env

  @spec repo_base_branch_env() :: String.t()
  def repo_base_branch_env, do: RepoRuntimeEnv.base_branch_env()

  @spec repo_branch_work_prefix_env() :: String.t()
  def repo_branch_work_prefix_env, do: RepoRuntimeEnv.branch_work_prefix_env()

  @spec provider_kind_env() :: String.t()
  def provider_kind_env, do: @provider_kind_env

  @spec provider_repository_env() :: String.t()
  def provider_repository_env, do: @provider_repository_env

  @spec provider_api_base_url_env() :: String.t()
  def provider_api_base_url_env, do: @provider_api_base_url_env

  @spec provider_web_base_url_env() :: String.t()
  def provider_web_base_url_env, do: @provider_web_base_url_env

  @spec provider_http_timeout_seconds_env() :: String.t()
  def provider_http_timeout_seconds_env, do: @provider_http_timeout_seconds_env

  @spec provider_max_http_retries_env() :: String.t()
  def provider_max_http_retries_env, do: @provider_max_http_retries_env

  @spec provider_retry_backoff_seconds_env() :: String.t()
  def provider_retry_backoff_seconds_env, do: @provider_retry_backoff_seconds_env

  @spec repo_path(map()) :: String.t() | nil
  def repo_path(env), do: env |> value(@repo_path_env) |> blank_to_nil()

  @spec repo_remote(map()) :: String.t() | nil
  def repo_remote(env), do: env |> value(@repo_remote_env) |> blank_to_nil()

  @spec repo_remote_url(map()) :: String.t() | nil
  def repo_remote_url(env), do: first_present(env, [@repo_remote_url_env, @source_repo_remote_url_env])

  @spec repo_base_branch(map()) :: String.t() | nil
  def repo_base_branch(env), do: first_present(env, [RepoRuntimeEnv.base_branch_env(), @source_repo_base_branch_env])

  @spec repo_branch_work_prefix(map()) :: String.t() | nil
  def repo_branch_work_prefix(env), do: env |> value(RepoRuntimeEnv.branch_work_prefix_env()) |> blank_to_nil()

  @spec provider_kind(map()) :: String.t() | nil
  def provider_kind(env), do: first_present(env, [@provider_kind_env, @source_provider_kind_env])

  @spec provider_repository(map()) :: String.t() | nil
  def provider_repository(env), do: first_present(env, [@provider_repository_env, @source_provider_repository_env])

  @spec provider_api_base_url(map()) :: String.t() | nil
  def provider_api_base_url(env), do: env |> value(@provider_api_base_url_env) |> blank_to_nil()

  @spec provider_web_base_url(map()) :: String.t() | nil
  def provider_web_base_url(env), do: env |> value(@provider_web_base_url_env) |> blank_to_nil()

  @spec provider_http_timeout_seconds(map()) :: String.t() | nil
  def provider_http_timeout_seconds(env), do: env |> value(@provider_http_timeout_seconds_env) |> blank_to_nil()

  @spec provider_max_http_retries(map()) :: String.t() | nil
  def provider_max_http_retries(env), do: env |> value(@provider_max_http_retries_env) |> blank_to_nil()

  @spec provider_retry_backoff_seconds(map()) :: String.t() | nil
  def provider_retry_backoff_seconds(env), do: env |> value(@provider_retry_backoff_seconds_env) |> blank_to_nil()

  @spec put_provider_repository(map(), term()) :: map()
  def put_provider_repository(env, value), do: maybe_put(env, @provider_repository_env, value)

  defp first_present(env, keys) when is_map(env) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      env
      |> value(key)
      |> blank_to_nil()
    end)
  end

  defp value(env, key) when is_map(env) and is_binary(key), do: Map.get(env, key)

  defp maybe_put(env, _key, nil), do: env
  defp maybe_put(env, _key, ""), do: env
  defp maybe_put(env, key, value) when is_map(env) and is_binary(key) and is_binary(value), do: Map.put(env, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
