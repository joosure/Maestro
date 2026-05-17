defmodule SymphonyElixir.Agent.Credential.Accounts.Options do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.OpenCode.CredentialEnv, as: OpenCodeCredentialEnv

  @spec attrs(keyword(), keyword()) :: keyword()
  def attrs(opts, extra_attrs) do
    opts
    |> Keyword.take([:email, :worker_host, :daily_token_budget, :enabled, :env_name])
    |> Keyword.merge(extra_attrs)
  end

  @spec required_token(keyword(), term()) :: {:ok, String.t()} | {:error, term()}
  def required_token(opts, missing_reason) do
    case Keyword.get(opts, :token) do
      token when is_binary(token) ->
        token = String.trim(token)

        if token == "" do
          {:error, missing_reason}
        else
          {:ok, token}
        end

      _token ->
        {:error, missing_reason}
    end
  end

  @spec opencode_env_name(keyword()) :: {:ok, String.t()} | {:error, term()}
  def opencode_env_name(opts) do
    case normalize_env_name(Keyword.get(opts, :env_name)) do
      {:ok, env_name} -> {:ok, env_name}
      :missing -> {:error, :missing_opencode_env_name}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_env_name(env_name) when is_binary(env_name) do
    env_name = String.trim(env_name)

    cond do
      env_name == "" -> :missing
      OpenCodeCredentialEnv.valid_env_name?(env_name) -> {:ok, env_name}
      true -> {:error, {:invalid_opencode_env_name, env_name}}
    end
  end

  defp normalize_env_name(_env_name), do: :missing
end
