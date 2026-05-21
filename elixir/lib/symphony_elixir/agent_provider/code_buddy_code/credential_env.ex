defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.CredentialEnv do
  @moduledoc """
  CodeBuddy Code managed-credential environment contract.
  """

  @env_token_credential_kind "codebuddy_env_token"
  @api_key_env "CODEBUDDY_API_KEY"
  @auth_token_env "CODEBUDDY_AUTH_TOKEN"
  @api_key_disabled_env "CODEBUDDY_API_KEY_DISABLED"
  @base_url_env "CODEBUDDY_BASE_URL"
  @internet_environment_env "CODEBUDDY_INTERNET_ENVIRONMENT"
  @internet_environments ~w(public internal ioa)

  @spec env_token_credential_kind() :: String.t()
  def env_token_credential_kind, do: @env_token_credential_kind

  @spec api_key_env() :: String.t()
  def api_key_env, do: @api_key_env

  @spec auth_token_env() :: String.t()
  def auth_token_env, do: @auth_token_env

  @spec api_key_disabled_env() :: String.t()
  def api_key_disabled_env, do: @api_key_disabled_env

  @spec base_url_env() :: String.t()
  def base_url_env, do: @base_url_env

  @spec internet_environment_env() :: String.t()
  def internet_environment_env, do: @internet_environment_env

  @spec internet_environments() :: [String.t()]
  def internet_environments, do: @internet_environments

  @spec normalize_internet_environment(term()) :: {:ok, String.t()} | {:error, term()}
  def normalize_internet_environment(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> String.downcase()

    cond do
      value == "" -> {:ok, "public"}
      value in @internet_environments -> {:ok, value}
      true -> {:error, {:invalid_codebuddy_internet_environment, value}}
    end
  end

  def normalize_internet_environment(nil), do: {:ok, "public"}
  def normalize_internet_environment(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_internet_environment()
  def normalize_internet_environment(_value), do: {:error, :invalid_codebuddy_internet_environment}

  @spec env_token_material(String.t(), String.t(), String.t()) :: map()
  def env_token_material(api_key, internet_environment, account_id) when is_binary(api_key) and is_binary(internet_environment) do
    %{
      env: materialized_env(api_key, internet_environment),
      summary: %{
        credential_kind: @env_token_credential_kind,
        auth_shape: @api_key_env,
        internet_environment: internet_environment,
        inherited_auth_env_unset: true,
        base_url_unset: true,
        setting_sources: "none",
        account_id_summary: account_id
      }
    }
  end

  @spec env_token_env(String.t() | nil, String.t() | nil) :: [{String.t(), String.t() | nil}]
  def env_token_env(api_key, internet_environment) do
    materialized_env(api_key, normalize_internet_environment!(internet_environment))
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  @spec materialized_env(String.t() | nil, String.t()) :: %{String.t() => String.t() | nil}
  def materialized_env(api_key, internet_environment) do
    %{
      @api_key_env => api_key,
      @auth_token_env => nil,
      @api_key_disabled_env => nil,
      @base_url_env => nil,
      @internet_environment_env => internet_environment_value(internet_environment)
    }
  end

  defp normalize_internet_environment!(value) do
    case normalize_internet_environment(value) do
      {:ok, internet_environment} -> internet_environment
      {:error, _reason} -> "public"
    end
  end

  defp internet_environment_value("internal"), do: "internal"
  defp internet_environment_value("ioa"), do: "ioa"
  defp internet_environment_value(_environment), do: nil
end
