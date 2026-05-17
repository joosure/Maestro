defmodule SymphonyElixir.LegalSourceInfo.RuntimeEnv do
  @moduledoc false

  @source_url_envs ~w(MAESTRO_SOURCE_URL SYMPHONY_SOURCE_URL)
  @source_revision_envs ~w(MAESTRO_SOURCE_REVISION SYMPHONY_SOURCE_REVISION)
  @default_source_url "https://github.com/joosure/Maestro"

  @spec source_url_envs() :: [String.t()]
  def source_url_envs, do: @source_url_envs

  @spec source_revision_envs() :: [String.t()]
  def source_revision_envs, do: @source_revision_envs

  @spec default_source_url() :: String.t()
  def default_source_url, do: @default_source_url

  @spec source_url(map() | [{String.t(), String.t()}] | nil) :: String.t()
  def source_url(env \\ System.get_env()) do
    env_value(env, @source_url_envs) || @default_source_url
  end

  @spec source_revision(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def source_revision(env \\ System.get_env()) do
    env_value(env, @source_revision_envs)
  end

  defp env_value(env, keys) when is_list(env), do: env |> Map.new() |> env_value(keys)

  defp env_value(env, keys) when is_map(env) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      env
      |> Map.get(key)
      |> blank_to_nil()
    end)
  end

  defp env_value(_env, _keys), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> blank_to_nil_trimmed()
  end

  defp blank_to_nil(_value), do: nil

  defp blank_to_nil_trimmed(""), do: nil
  defp blank_to_nil_trimmed(value), do: value
end
