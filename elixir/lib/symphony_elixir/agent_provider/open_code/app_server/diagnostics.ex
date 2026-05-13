defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Diagnostics do
  @moduledoc false

  require Logger

  @port_log_preview_bytes 1_000

  @spec log_port_output(String.t(), String.t()) :: :ok
  def log_port_output(stream_label, line) when is_binary(stream_label) and is_binary(line) do
    text = line |> String.trim_trailing() |> truncate_output()
    if text != "", do: Logger.debug("OpenCode #{stream_label} output: #{text}")
    :ok
  end

  @spec preview_value(term()) :: String.t()
  def preview_value(value), do: value |> inspect(limit: 10, printable_limit: 300) |> truncate_output()

  @spec compact_details(map()) :: map()
  def compact_details(details) when is_map(details) do
    Enum.reduce(details, %{}, fn
      {_key, nil}, acc -> acc
      {_key, ""}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp truncate_output(text) when byte_size(text) > @port_log_preview_bytes,
    do: binary_part(text, 0, @port_log_preview_bytes) <> "..."

  defp truncate_output(text), do: text
end
