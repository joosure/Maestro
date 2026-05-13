defmodule SymphonyWorkerDaemon.CapacityManager.Leases do
  @moduledoc false

  alias SymphonyWorkerDaemon.CapacityManager.TenantKey

  @spec add(map(), String.t(), map(), integer()) :: map()
  def add(leases, lease_id, attrs, admitted_at_ms)
      when is_map(leases) and is_binary(lease_id) and is_map(attrs) and is_integer(admitted_at_ms) do
    Map.put(leases, lease_id, attrs |> Map.put(:tenant_key, TenantKey.from_attrs(attrs)) |> Map.put(:admitted_at_ms, admitted_at_ms))
  end

  @spec tenant_quota_exceeded?(map(), pos_integer() | nil, map()) :: boolean()
  def tenant_quota_exceeded?(_leases, nil, _attrs), do: false

  def tenant_quota_exceeded?(leases, max_sessions_per_tenant, attrs)
      when is_map(leases) and is_integer(max_sessions_per_tenant) and is_map(attrs) do
    key = TenantKey.from_attrs(attrs)
    active_sessions = leases |> Map.values() |> Enum.count(&(Map.get(&1, :tenant_key) == key))
    active_sessions >= max_sessions_per_tenant
  end
end
