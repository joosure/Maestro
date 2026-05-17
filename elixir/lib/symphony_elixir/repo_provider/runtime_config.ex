defmodule SymphonyElixir.RepoProvider.RuntimeConfig do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Config
  alias SymphonyElixir.RepoProvider.Defaults
  alias SymphonyElixir.RepoProvider.RuntimeEnv

  @default_kind Defaults.default_kind()

  @spec from_env(map() | [{String.t(), String.t()}]) :: Config.t()
  def from_env(env) when is_map(env) do
    %Config{
      path: RuntimeEnv.repo_path(env),
      base_branch: RuntimeEnv.repo_base_branch(env),
      remote: %{
        name: RuntimeEnv.repo_remote(env),
        url: RuntimeEnv.repo_remote_url(env)
      },
      branch: %{
        work_prefix: RuntimeEnv.repo_branch_work_prefix(env)
      },
      provider: %{
        kind: RuntimeEnv.provider_kind(env) || @default_kind,
        repository: RuntimeEnv.provider_repository(env),
        api_base_url: RuntimeEnv.provider_api_base_url(env),
        web_base_url: RuntimeEnv.provider_web_base_url(env)
      },
      runtime: %{
        http_timeout_seconds: RuntimeEnv.provider_http_timeout_seconds(env),
        max_http_retries: RuntimeEnv.provider_max_http_retries(env),
        retry_backoff_seconds: RuntimeEnv.provider_retry_backoff_seconds(env)
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
      {RuntimeEnv.repo_path_env(), Config.path(repo)},
      {RuntimeEnv.repo_remote_env(), Config.remote_name(repo)},
      {RuntimeEnv.repo_remote_url_env(), Config.remote_url(repo)},
      {RuntimeEnv.repo_base_branch_env(), Config.base_branch(repo)},
      {RuntimeEnv.repo_branch_work_prefix_env(), Config.branch_work_prefix(repo)},
      {RuntimeEnv.provider_kind_env(), current_kind(repo)},
      {RuntimeEnv.provider_repository_env(), Config.repository(repo)},
      {RuntimeEnv.provider_api_base_url_env(), Config.api_base_url(repo)},
      {RuntimeEnv.provider_web_base_url_env(), Config.web_base_url(repo)},
      {RuntimeEnv.provider_http_timeout_seconds_env(), Config.runtime_http_timeout_seconds(repo)},
      {RuntimeEnv.provider_max_http_retries_env(), Config.runtime_max_http_retries(repo)},
      {RuntimeEnv.provider_retry_backoff_seconds_env(), Config.runtime_retry_backoff_seconds(repo)}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  def to_env(_repo), do: [{RuntimeEnv.provider_kind_env(), @default_kind}]

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
end
