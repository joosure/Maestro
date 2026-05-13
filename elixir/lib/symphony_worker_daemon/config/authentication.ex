defmodule SymphonyWorkerDaemon.Config.Authentication do
  @moduledoc false

  alias SymphonyWorkerDaemon.Config.Options

  @spec resolve(keyword(), map(), String.t()) :: {:ok, String.t() | nil, boolean()} | {:error, String.t()}
  def resolve(opts, deps, default_token_env) when is_list(opts) and is_map(deps) and is_binary(default_token_env) do
    direct_token = opts |> Options.last_value(:token) |> Options.normalize_optional_string()
    token_env = opts |> Options.last_value(:token_env) |> Options.normalize_optional_string()
    allow_unauthenticated? = Keyword.get(opts, :allow_unauthenticated, false)

    cond do
      direct_token && token_env ->
        {:error, "Pass only one of --token or --token-env for worker daemon authentication."}

      allow_unauthenticated? && (direct_token || token_env) ->
        {:error, "Pass either worker daemon authentication or --allow-unauthenticated, not both."}

      direct_token ->
        {:ok, direct_token, false}

      token_env ->
        with {:ok, token} <- token_from_env(token_env, deps) do
          {:ok, token, false}
        end

      allow_unauthenticated? ->
        {:ok, nil, true}

      true ->
        case deps.getenv.(default_token_env) |> Options.normalize_optional_string() do
          token when is_binary(token) ->
            {:ok, token, false}

          nil ->
            {:error, "Worker daemon authentication token is required. Set #{default_token_env}, pass --token-env, or use --allow-unauthenticated for isolated local development."}
        end
    end
  end

  defp token_from_env(token_env, deps) do
    case deps.getenv.(token_env) |> Options.normalize_optional_string() do
      token when is_binary(token) -> {:ok, token}
      nil -> {:error, "Environment variable #{token_env} is not set or is empty."}
    end
  end
end
