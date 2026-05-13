defmodule SymphonyElixir.Agent.Credential.Accounts.Environment do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Accounts.Secret
  alias SymphonyElixir.Agent.Credential.Store

  @spec credential_env(Store.account() | nil) :: [{String.t(), String.t()}]
  def credential_env(nil), do: []

  def credential_env(%{agent_provider_kind: "claude_code", credential_kind: "claude_oauth_token"} = account) do
    [
      {"CLAUDE_CODE_OAUTH_TOKEN", Secret.read(account.secret_file)},
      {"CLAUDE_CONFIG_DIR", account.auth_dir},
      {"ANTHROPIC_API_KEY", ""}
    ]
    |> reject_blank_env()
  end

  def credential_env(%{agent_provider_kind: "claude_code", credential_kind: "claude_config"} = account) do
    [{"CLAUDE_CONFIG_DIR", account.auth_dir}, {"ANTHROPIC_API_KEY", ""}]
  end

  def credential_env(%{agent_provider_kind: "opencode", credential_kind: "opencode_env_token", env_name: env_name} = account)
      when is_binary(env_name) and env_name != "" do
    [{env_name, Secret.read(account.secret_file)}]
    |> reject_blank_env()
  end

  def credential_env(_account), do: []

  defp reject_blank_env(env) do
    Enum.reject(env, fn
      {"ANTHROPIC_API_KEY", ""} -> false
      {_key, value} -> is_nil(value) or value == ""
    end)
  end
end
