defmodule SymphonyWorkerDaemon.BridgeProxy.PortReservation do
  @moduledoc false

  @spec reserve(:inet.ip_address()) :: {:ok, pos_integer()} | {:error, term()}
  def reserve(ip) do
    with {:ok, socket} <- :gen_tcp.listen(0, [:binary, active: false, ip: ip]),
         {:ok, port} <- :inet.port(socket),
         :ok <- :gen_tcp.close(socket) do
      {:ok, port}
    else
      {:error, reason} -> {:error, {:dynamic_tool_bridge_proxy_port_unavailable, reason}}
    end
  end
end
