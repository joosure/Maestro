defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.RuntimeEnv do
  @moduledoc false

  @endpoint_env "SYMPHONY_WORKER_DAEMON_ENDPOINT"
  @endpoints_env "SYMPHONY_WORKER_DAEMON_ENDPOINTS"
  @token_env "SYMPHONY_WORKER_DAEMON_TOKEN"

  @spec endpoint_env() :: String.t()
  def endpoint_env, do: @endpoint_env

  @spec endpoints_env() :: String.t()
  def endpoints_env, do: @endpoints_env

  @spec token_env() :: String.t()
  def token_env, do: @token_env

  @spec endpoint(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def endpoint(env \\ System.get_env()), do: env_value(env, @endpoint_env)

  @spec endpoints(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def endpoints(env \\ System.get_env()), do: env_value(env, @endpoints_env)

  @spec token(map() | [{String.t(), String.t()}] | nil) :: String.t() | nil
  def token(env \\ System.get_env()), do: env_value(env, @token_env)

  defp env_value(env, key) when is_list(env), do: env |> Map.new() |> env_value(key)
  defp env_value(env, key) when is_map(env) and is_binary(key), do: env |> Map.get(key) |> blank_to_nil()
  defp env_value(_env, _key), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value) |> blank_to_nil_trimmed()
  defp blank_to_nil(value), do: value

  defp blank_to_nil_trimmed(""), do: nil
  defp blank_to_nil_trimmed(value), do: value
end
