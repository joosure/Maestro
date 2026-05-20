defmodule SymphonyElixir.Agent.Credential.Accounts.Environment do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.Secret
  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider.ClaudeCode.CredentialEnv, as: ClaudeCredentialEnv
  alias SymphonyElixir.AgentProvider.CodeBuddyCode.CredentialEnv, as: CodeBuddyCredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.CredentialEnv, as: OpenCodeCredentialEnv

  @claude_code_kind Kinds.claude_code()
  @claude_oauth_token_credential_kind ClaudeCredentialEnv.oauth_token_credential_kind()
  @claude_config_credential_kind ClaudeCredentialEnv.config_credential_kind()
  @anthropic_api_key_env ClaudeCredentialEnv.anthropic_api_key_env()
  @codebuddy_code_kind Kinds.codebuddy_code()
  @codebuddy_env_token_credential_kind CodeBuddyCredentialEnv.env_token_credential_kind()
  @opencode_kind Kinds.opencode()
  @opencode_env_token_credential_kind OpenCodeCredentialEnv.env_token_credential_kind()

  @spec credential_env(Store.account() | nil) :: [{String.t(), String.t()}]
  def credential_env(nil), do: []

  def credential_env(%{agent_provider_kind: @claude_code_kind, credential_kind: @claude_oauth_token_credential_kind} = account) do
    ClaudeCredentialEnv.oauth_token_env(Secret.read(account.secret_file), account.auth_dir)
  end

  def credential_env(%{agent_provider_kind: @claude_code_kind, credential_kind: @claude_config_credential_kind} = account) do
    ClaudeCredentialEnv.config_env(account.auth_dir)
  end

  def credential_env(%{agent_provider_kind: @opencode_kind, credential_kind: @opencode_env_token_credential_kind, env_name: env_name} = account)
      when is_binary(env_name) and env_name != "" do
    OpenCodeCredentialEnv.env_token_env(env_name, Secret.read(account.secret_file))
    |> reject_blank_env()
  end

  def credential_env(%{agent_provider_kind: @codebuddy_code_kind, credential_kind: @codebuddy_env_token_credential_kind} = account) do
    CodeBuddyCredentialEnv.env_token_env(Secret.read(account.secret_file), Map.get(account, :internet_environment))
  end

  def credential_env(_account), do: []

  defp reject_blank_env(env) do
    Enum.reject(env, fn
      {@anthropic_api_key_env, ""} -> false
      {_key, value} -> is_nil(value) or value == ""
    end)
  end
end
