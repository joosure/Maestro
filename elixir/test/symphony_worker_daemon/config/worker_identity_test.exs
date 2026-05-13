defmodule SymphonyWorkerDaemon.Config.WorkerIdentityTest do
  use ExUnit.Case, async: true

  alias SymphonyWorkerDaemon.Config.WorkerIdentity

  test "uses explicit worker id before host identity" do
    deps = %{hostname: fn -> {:ok, "host-a"} end}

    assert {:ok, "worker-a"} = WorkerIdentity.resolve([worker_id: "worker-a"], deps)
  end

  test "uses host identity and local process identity when host lookup fails" do
    assert {:ok, "host-a"} = WorkerIdentity.resolve([], %{hostname: fn -> {:ok, "host-a"} end})
    assert {:ok, "worker-local"} = WorkerIdentity.resolve([], %{hostname: fn -> {:error, :nxdomain} end})
  end
end
