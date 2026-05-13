defmodule SymphonyWorkerDaemon.CLI.Output do
  @moduledoc false

  @spec started(keyword()) :: :ok
  def started(opts) when is_list(opts) do
    IO.puts("Symphony worker daemon listening on #{server_url(opts)}")
    IO.puts("worker_id=#{Keyword.fetch!(opts, :worker_id)} daemon_instance_id=#{Keyword.fetch!(opts, :daemon_instance_id)}")
  end

  defp server_url(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    "http://#{format_host(host)}:#{port}"
  end

  defp format_host(host) when is_binary(host) do
    if String.contains?(host, ":") and not String.starts_with?(host, "[") do
      "[" <> host <> "]"
    else
      host
    end
  end
end
