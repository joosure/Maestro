defmodule SymphonyWorkerDaemon.Session.Server.Payloads do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields

  @session_id_key ProtocolFields.session_id()
  @lease_id_key ProtocolFields.lease_id()
  @status_key ProtocolFields.status()
  @run_id_key ProtocolFields.run_id()
  @owner_key ProtocolFields.owner()
  @tenant_id_key ProtocolFields.tenant_id()
  @provider_kind_key ProtocolFields.provider_kind()
  @worker_pool_key ProtocolFields.worker_pool()
  @cwd_key ProtocolFields.cwd()
  @os_pid_key ProtocolFields.os_pid()
  @exit_status_key ProtocolFields.exit_status()
  @started_at_ms_key ProtocolFields.started_at_ms()
  @updated_at_ms_key ProtocolFields.updated_at_ms()
  @dynamic_tool_bridge_key ProtocolFields.dynamic_tool_bridge()
  @caller_key ProtocolFields.caller()

  @spec status(map()) :: map()
  def status(state) do
    %{
      @session_id_key => state.session_id,
      @lease_id_key => state.lease_id,
      @status_key => state.status,
      @cwd_key => state.cwd,
      @os_pid_key => state.os_pid,
      @exit_status_key => state.exit_status,
      "output_bytes" => state.output_bytes,
      "output_truncated" => state.output_truncated?,
      "next_event_id" => state.next_event_id,
      @started_at_ms_key => state.started_at_ms,
      @updated_at_ms_key => state.updated_at_ms,
      "lost_reason" => state.lost_reason,
      "stop_reason" => state.stop_reason,
      @dynamic_tool_bridge_key => bridge_status(Map.get(state, :bridge_proxy))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec summary(map()) :: map()
  def summary(state) do
    caller = caller_request(state.request)

    %{
      @session_id_key => state.session_id,
      @lease_id_key => state.lease_id,
      @status_key => state.status,
      @run_id_key => Map.get(state.request, @run_id_key),
      @owner_key => Map.get(caller, @owner_key),
      @tenant_id_key => Map.get(caller, @tenant_id_key),
      @provider_kind_key => Map.get(caller, @provider_kind_key),
      @worker_pool_key => Map.get(caller, @worker_pool_key),
      @cwd_key => state.cwd,
      @os_pid_key => state.os_pid,
      @exit_status_key => state.exit_status,
      "output_bytes" => state.output_bytes,
      "output_truncated" => state.output_truncated?,
      "next_event_id" => state.next_event_id,
      @started_at_ms_key => state.started_at_ms,
      @updated_at_ms_key => state.updated_at_ms,
      "lost_reason" => state.lost_reason,
      "stop_reason" => state.stop_reason,
      "dynamic_tool_bridge_enabled" => not is_nil(Map.get(state, :bridge_proxy))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp caller_request(%{@caller_key => caller}) when is_map(caller), do: caller
  defp caller_request(_request), do: %{}

  defp bridge_status(%{base_url: base_url, port: port}), do: %{"base_url" => base_url, "port" => port}
  defp bridge_status(_bridge_proxy), do: nil
end
