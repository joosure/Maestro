defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.ReleaseCredentialPreflight do
  @moduledoc false

  @behaviour SymphonyElixir.AgentProvider.ReleaseCredentialPreflight

  alias SymphonyElixir.AgentProvider.CodeBuddyCode.CredentialEnv
  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight

  @provider_kind Kinds.codebuddy_code()
  @token_env_config "SYMPHONY_CODEBUDDY_TOKEN_ENV"
  @default_token_env CredentialEnv.api_key_env()
  @verify_command_env "SYMPHONY_CODEBUDDY_VERIFY_COMMAND"

  @impl true
  def provider_kind, do: @provider_kind

  @impl true
  def login_plan(_account_id, env_map) do
    ReleaseCredentialPreflight.env_token_login_plan(env_map,
      token_env_config: @token_env_config,
      default_token_env: @default_token_env,
      login_option_specs: [
        {:internet_environment, {:env, CredentialEnv.internet_environment_env(), "public"}},
        {:token, :token}
      ]
    )
  end

  @impl true
  def verify_opts(env_map, settings) do
    ReleaseCredentialPreflight.auth_probe_verify_opts(env_map, settings, @verify_command_env)
  end
end
