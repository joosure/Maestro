defmodule SymphonyElixir.AgentProvider.Codex.ReleaseCredentialPreflight do
  @moduledoc false

  @behaviour SymphonyElixir.AgentProvider.ReleaseCredentialPreflight

  alias SymphonyElixir.AgentProvider.Codex.CredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight

  @provider_kind Kinds.codex()
  @token_env_config "SYMPHONY_CODEX_TOKEN_ENV"
  @default_token_env CredentialEnv.api_key_env()
  @verify_command_env "SYMPHONY_CODEX_VERIFY_COMMAND"

  @impl true
  def provider_kind, do: @provider_kind

  @impl true
  def login_plan(_account_id, env_map) do
    ReleaseCredentialPreflight.env_token_login_plan(env_map,
      token_env_config: @token_env_config,
      default_token_env: @default_token_env,
      login_option_specs: [
        {:token, :token}
      ]
    )
  end

  @impl true
  def verify_opts(env_map, _settings) do
    ReleaseCredentialPreflight.command_verify_opts(env_map, @verify_command_env)
  end
end
