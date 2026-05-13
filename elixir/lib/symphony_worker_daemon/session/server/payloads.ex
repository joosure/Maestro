defmodule SymphonyWorkerDaemon.Session.Server.Payloads do
  @moduledoc false

  @spec status(map()) :: map()
  def status(state) do
    %{
      "session_id" => state.session_id,
      "lease_id" => state.lease_id,
      "status" => state.status,
      "cwd" => state.cwd,
      "os_pid" => state.os_pid,
      "exit_status" => state.exit_status,
      "output_bytes" => state.output_bytes,
      "output_truncated" => state.output_truncated?,
      "next_event_id" => state.next_event_id,
      "started_at_ms" => state.started_at_ms,
      "updated_at_ms" => state.updated_at_ms,
      "lost_reason" => state.lost_reason,
      "stop_reason" => state.stop_reason,
      "dynamic_tool_bridge" => bridge_status(Map.get(state, :bridge_proxy))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec summary(map()) :: map()
  def summary(state) do
    caller = caller_request(state.request)

    %{
      "session_id" => state.session_id,
      "lease_id" => state.lease_id,
      "status" => state.status,
      "run_id" => state.request["run_id"],
      "owner" => caller["owner"],
      "tenant_id" => caller["tenant_id"],
      "provider_kind" => caller["provider_kind"],
      "worker_pool" => caller["worker_pool"],
      "cwd" => state.cwd,
      "os_pid" => state.os_pid,
      "exit_status" => state.exit_status,
      "output_bytes" => state.output_bytes,
      "output_truncated" => state.output_truncated?,
      "next_event_id" => state.next_event_id,
      "started_at_ms" => state.started_at_ms,
      "updated_at_ms" => state.updated_at_ms,
      "lost_reason" => state.lost_reason,
      "stop_reason" => state.stop_reason,
      "dynamic_tool_bridge_enabled" => not is_nil(Map.get(state, :bridge_proxy))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp caller_request(%{"caller" => caller}) when is_map(caller), do: caller
  defp caller_request(_request), do: %{}

  defp bridge_status(%{base_url: base_url, port: port}), do: %{"base_url" => base_url, "port" => port}
  defp bridge_status(_bridge_proxy), do: nil
end
