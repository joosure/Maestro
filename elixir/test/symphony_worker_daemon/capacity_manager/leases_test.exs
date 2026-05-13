defmodule SymphonyWorkerDaemon.CapacityManager.LeasesTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.CapacityManager.Leases

  test "adds tenant key and admission timestamp to leases" do
    attrs = %{session_id: "session-1", caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}}

    leases = Leases.add(%{}, "lease-1", attrs, 123)

    assert %{
             "lease-1" => %{
               session_id: "session-1",
               tenant_key: "tenant-a:owner-a",
               admitted_at_ms: 123
             }
           } = leases
  end

  test "detects tenant quota with normalized tenant keys" do
    leases =
      %{}
      |> Leases.add("lease-1", %{caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}}, 100)
      |> Leases.add("lease-2", %{caller: %{"owner" => "owner-b", "tenant_id" => "tenant-b"}}, 101)

    assert Leases.tenant_quota_exceeded?(leases, 1, %{caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}})
    refute Leases.tenant_quota_exceeded?(leases, 1, %{caller: %{"owner" => "owner-c", "tenant_id" => "tenant-c"}})
    refute Leases.tenant_quota_exceeded?(leases, nil, %{caller: %{"owner" => "owner-a", "tenant_id" => "tenant-a"}})
  end
end
