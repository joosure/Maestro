defmodule SymphonyElixir.AgentProvider.OpenCode.CredentialEnv do
  @moduledoc """
  Credential materialization contract for the OpenCode provider.
  """

  @env_token_credential_kind "opencode_env_token"
  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec env_token_credential_kind() :: String.t()
  def env_token_credential_kind, do: @env_token_credential_kind

  @spec env_name_pattern() :: Regex.t()
  def env_name_pattern, do: @env_name_pattern

  @spec valid_env_name?(term()) :: boolean()
  def valid_env_name?(env_name) when is_binary(env_name), do: Regex.match?(@env_name_pattern, env_name)
  def valid_env_name?(_env_name), do: false

  @spec env_token_material(String.t(), String.t(), String.t()) :: map()
  def env_token_material(env_name, token, account_id) when is_binary(env_name) and is_binary(token) do
    %{
      env: %{env_name => token},
      summary: %{
        credential_kind: @env_token_credential_kind,
        env_name: env_name,
        account_id_summary: account_id
      }
    }
  end

  @spec env_token_env(String.t(), String.t() | nil) :: [{String.t(), String.t()}]
  def env_token_env(env_name, token) when is_binary(env_name) and env_name != "" do
    [{env_name, token}]
  end

  def env_token_env(_env_name, _token), do: []
end
