defmodule SymphonyElixir.RepoProvider.RuntimeConfig do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Config

  @default_kind "github"

  @spec from_env(map() | [{String.t(), String.t()}]) :: Config.t()
  def from_env(env) when is_map(env) do
    %Config{
      path: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PATH")),
      base_branch: blank_to_nil(env_value(env, "SYMPHONY_REPO_BASE_BRANCH", "SOURCE_REPO_BASE_BRANCH")),
      remote: %{
        name: blank_to_nil(Map.get(env, "SYMPHONY_REPO_REMOTE")),
        url: blank_to_nil(env_value(env, "SYMPHONY_REPO_REMOTE_URL", "SOURCE_REPO_URL"))
      },
      branch: %{
        work_prefix: blank_to_nil(Map.get(env, "SYMPHONY_REPO_BRANCH_WORK_PREFIX"))
      },
      provider: %{
        kind: env_value(env, "SYMPHONY_REPO_PROVIDER_KIND", "SOURCE_REPO_PROVIDER_KIND") || @default_kind,
        repository: blank_to_nil(env_value(env, "SYMPHONY_REPO_PROVIDER_REPOSITORY", "SOURCE_REPO_PROVIDER_REPOSITORY")),
        api_base_url: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PROVIDER_API_BASE_URL")),
        web_base_url: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL"))
      },
      runtime: %{
        http_timeout_seconds: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PROVIDER_HTTP_TIMEOUT_SECONDS")),
        max_http_retries: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES")),
        retry_backoff_seconds: blank_to_nil(Map.get(env, "SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS"))
      }
    }
  end

  def from_env(env) when is_list(env) do
    env
    |> Map.new()
    |> from_env()
  end

  @spec to_env(map()) :: [{String.t(), String.t()}]
  def to_env(repo) when is_map(repo) do
    [
      {"SYMPHONY_REPO_PATH", Config.path(repo)},
      {"SYMPHONY_REPO_REMOTE", Config.remote_name(repo)},
      {"SYMPHONY_REPO_REMOTE_URL", Config.remote_url(repo)},
      {"SYMPHONY_REPO_BASE_BRANCH", Config.base_branch(repo)},
      {"SYMPHONY_REPO_BRANCH_WORK_PREFIX", Config.branch_work_prefix(repo)},
      {"SYMPHONY_REPO_PROVIDER_KIND", current_kind(repo)},
      {"SYMPHONY_REPO_PROVIDER_REPOSITORY", Config.repository(repo)},
      {"SYMPHONY_REPO_PROVIDER_API_BASE_URL", Config.api_base_url(repo)},
      {"SYMPHONY_REPO_PROVIDER_WEB_BASE_URL", Config.web_base_url(repo)},
      {"SYMPHONY_REPO_PROVIDER_HTTP_TIMEOUT_SECONDS", Config.runtime_http_timeout_seconds(repo)},
      {"SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES", Config.runtime_max_http_retries(repo)},
      {"SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS", Config.runtime_retry_backoff_seconds(repo)}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def to_env(_repo), do: [{"SYMPHONY_REPO_PROVIDER_KIND", @default_kind}]

  @spec apply_provider_override(map(), nil | String.t()) :: map()
  def apply_provider_override(repo, nil) when is_map(repo), do: repo

  def apply_provider_override(repo, kind) when is_map(repo) and is_binary(kind) do
    Config.with_kind(repo, kind)
  end

  @spec current_kind(map()) :: String.t()
  def current_kind(repo) when is_map(repo) do
    case Config.kind(repo) do
      kind when is_binary(kind) and kind != "" -> kind
      _other -> @default_kind
    end
  end

  def current_kind(_repo), do: @default_kind

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp env_value(env, primary, secondary) when is_map(env) do
    case blank_to_nil(Map.get(env, primary)) do
      nil -> blank_to_nil(Map.get(env, secondary))
      value -> value
    end
  end
end
