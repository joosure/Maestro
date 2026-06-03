defmodule SymphonyElixir.AgentProvider.ClaudeCode.CredentialEnv do
  @moduledoc """
  Claude Code managed-credential environment contract.
  """

  alias SymphonyElixir.AgentProvider.ModelCredentialEnv

  @oauth_token_credential_kind "claude_oauth_token"
  @config_credential_kind "claude_config"
  @oauth_token_env "CLAUDE_CODE_OAUTH_TOKEN"
  @config_dir_env "CLAUDE_CONFIG_DIR"
  @anthropic_api_key_env ModelCredentialEnv.anthropic_api_key_env()
  @default_config_dir "~/.claude"

  @spec oauth_token_credential_kind() :: String.t()
  def oauth_token_credential_kind, do: @oauth_token_credential_kind

  @spec config_credential_kind() :: String.t()
  def config_credential_kind, do: @config_credential_kind

  @spec oauth_token_env() :: String.t()
  def oauth_token_env, do: @oauth_token_env

  @spec config_dir_env() :: String.t()
  def config_dir_env, do: @config_dir_env

  @spec anthropic_api_key_env() :: String.t()
  def anthropic_api_key_env, do: @anthropic_api_key_env

  @spec default_config_dir() :: String.t()
  def default_config_dir, do: @default_config_dir

  @spec oauth_token_env(String.t() | nil, Path.t() | nil) :: [{String.t(), String.t()}]
  def oauth_token_env(token, auth_dir) do
    [
      {@oauth_token_env, token},
      {@config_dir_env, auth_dir},
      {@anthropic_api_key_env, ""}
    ]
    |> reject_blank_env()
  end

  @spec config_env(Path.t() | nil) :: [{String.t(), String.t()}]
  def config_env(auth_dir), do: [{@config_dir_env, auth_dir}, {@anthropic_api_key_env, ""}]

  @spec materialized_oauth_token_env(String.t(), Path.t()) :: %{String.t() => String.t()}
  def materialized_oauth_token_env(token, auth_dir), do: Map.new(oauth_token_env(token, auth_dir))

  @spec materialized_config_env(Path.t()) :: %{String.t() => String.t()}
  def materialized_config_env(auth_dir), do: Map.new(config_env(auth_dir))

  defp reject_blank_env(env) do
    Enum.reject(env, fn
      {@anthropic_api_key_env, ""} -> false
      {_key, value} -> is_nil(value) or value == ""
    end)
  end
end
