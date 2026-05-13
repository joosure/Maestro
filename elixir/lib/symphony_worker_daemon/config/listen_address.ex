defmodule SymphonyWorkerDaemon.Config.ListenAddress do
  @moduledoc false

  alias SymphonyWorkerDaemon.Config.Options

  @spec resolve(keyword(), String.t()) :: {:ok, String.t(), :inet.ip_address()} | {:error, String.t()}
  def resolve(opts, default_host) when is_list(opts) and is_binary(default_host) do
    host = opts |> Options.last_value(:host) |> Options.normalize_optional_string() || default_host

    case parse_ip(host) do
      {:ok, ip} -> {:ok, host, ip}
      {:error, reason} -> {:error, "Invalid worker daemon host #{inspect(host)}: #{inspect(reason)}"}
    end
  end

  defp parse_ip("localhost"), do: {:ok, {127, 0, 0, 1}}

  defp parse_ip(host) when is_binary(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
  end
end
