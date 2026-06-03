defmodule SymphonyElixir.AgentProvider.OpenCode.ReleaseCredentialPreflight do
  @moduledoc false

  @behaviour SymphonyElixir.AgentProvider.ReleaseCredentialPreflight

  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.CredentialEnv
  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight
  alias SymphonyElixir.Platform.Env

  @provider_kind Kinds.opencode()
  @token_env_config "SYMPHONY_OPENCODE_TOKEN_ENV"
  @credential_env_name_config "SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME"
  @verify_command_env "SYMPHONY_OPENCODE_VERIFY_COMMAND"

  @impl true
  def provider_kind, do: @provider_kind

  @impl true
  def login_plan(account_id, env_map) do
    with {:ok, token_context} <- token_context(account_id, env_map) do
      ReleaseCredentialPreflight.env_token_login_plan(env_map,
        token_env_config: @token_env_config,
        default_token_env: Map.fetch!(token_context, :default_token_env),
        login_option_specs: [
          {:env_name, {:value, :env_name}},
          {:token, :token}
        ],
        token_context: token_context
      )
    end
  end

  @impl true
  def verify_opts(env_map, settings) do
    ReleaseCredentialPreflight.auth_probe_verify_opts(env_map, settings, @verify_command_env)
  end

  defp token_context(account_id, env_map) do
    case credential_env_name(account_id, env_map) do
      {:ok, env_name} ->
        {:ok, %{default_token_env: env_name, env_name: env_name}}

      {:error, reason} ->
        missing_env_name = missing_credential_env_name(account_id)

        case {reason, Env.value(env_map, @token_env_config)} do
          {^missing_env_name, nil} ->
            {:ok,
             %{
               credential_hint: unknown_account_hint(),
               default_token_env: @credential_env_name_config
             }}

          _other ->
            {:error, reason}
        end
    end
  end

  defp credential_env_name(account_id, env_map) do
    case Env.configured_env_name(env_map, @credential_env_name_config) do
      {:ok, env_name} ->
        {:ok, env_name}

      :missing ->
        case CredentialEnv.default_env_name(account_id) do
          {:ok, env_name} -> {:ok, env_name}
          :error -> {:error, missing_credential_env_name(account_id)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp missing_credential_env_name(account_id),
    do: "set #{@credential_env_name_config} for credential://#{@provider_kind}/#{account_id}"

  defp unknown_account_hint do
    "if this credential is not initialized or needs rotation, set #{@credential_env_name_config} to the environment variable name OpenCode should receive, then set that environment variable to the token or set #{@token_env_config} to another token environment variable name"
  end
end
