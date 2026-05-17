defmodule SymphonyElixir.AgentProvider.Codex.CredentialEnv do
  @moduledoc """
  Codex managed-credential environment contract.
  """

  @api_key_credential_kind "codex_api_key"
  @home_env "CODEX_HOME"
  @api_key_env "OPENAI_API_KEY"
  @auth_mode_key "auth_mode"
  @auth_mode_api_key "apikey"

  @spec api_key_credential_kind() :: String.t()
  def api_key_credential_kind, do: @api_key_credential_kind

  @spec home_env() :: String.t()
  def home_env, do: @home_env

  @spec api_key_env() :: String.t()
  def api_key_env, do: @api_key_env

  @spec auth_shape() :: String.t()
  def auth_shape, do: @home_env

  @spec materialized_env(Path.t()) :: %{String.t() => String.t()}
  def materialized_env(codex_home), do: %{@home_env => codex_home}

  @spec auth_payload(String.t()) :: %{String.t() => String.t()}
  def auth_payload(api_key), do: %{@auth_mode_key => @auth_mode_api_key, @api_key_env => api_key}
end
