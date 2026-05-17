defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.Connection do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Endpoint
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.RuntimeEnv

  @spec endpoint(Target.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def endpoint(%Target{} = target, opts \\ []) do
    [
      Keyword.get(opts, :worker_daemon_endpoint),
      metadata_value(target.metadata, :worker_daemon_endpoint),
      Application.get_env(:symphony_elixir, :worker_daemon_endpoint),
      RuntimeEnv.endpoint()
    ]
    |> Enum.find_value(&Endpoint.normalize/1)
    |> Endpoint.normalize_validated()
  end

  @spec token(keyword()) :: String.t() | nil
  def token(opts \\ []) do
    opts
    |> Keyword.get(:worker_daemon_token)
    |> normalize_optional_string()
    |> case do
      token when is_binary(token) ->
        token

      nil ->
        Application.get_env(:symphony_elixir, :worker_daemon_token)
        |> normalize_optional_string()
        |> case do
          token when is_binary(token) -> token
          nil -> RuntimeEnv.token()
        end
    end
  end

  @spec metadata_value(map() | term(), atom()) :: term()
  def metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  end

  def metadata_value(_metadata, _key), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
