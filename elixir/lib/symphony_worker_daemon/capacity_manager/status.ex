defmodule SymphonyWorkerDaemon.CapacityManager.Status do
  @moduledoc false

  @spec payload(map()) :: map()
  def payload(state) when is_map(state) do
    active_sessions = map_size(state.leases)

    %{
      status: status_name(state, active_sessions),
      active_sessions: active_sessions,
      max_sessions: state.max_sessions,
      max_sessions_per_tenant: state.max_sessions_per_tenant,
      active_tenants: active_tenant_count(state.leases),
      available_sessions: max(state.max_sessions - active_sessions, 0)
    }
  end

  defp status_name(%{unavailable?: true}, _active_sessions), do: :unavailable
  defp status_name(%{draining?: true}, _active_sessions), do: :draining
  defp status_name(%{max_sessions: max_sessions}, active_sessions) when active_sessions >= max_sessions, do: :full
  defp status_name(_state, _active_sessions), do: :ready

  defp active_tenant_count(leases) when is_map(leases) do
    leases
    |> Map.values()
    |> Enum.map(&Map.get(&1, :tenant_key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end
end
