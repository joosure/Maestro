defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.CandidatesTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.Candidates

  test "builds normalized endpoint and named-pool candidates" do
    target = Target.new(placement: :worker_daemon, worker_pool: "coding-linux", workspace_path: "/work")

    candidates =
      Candidates.build(target,
        worker_daemon_endpoints: " http://daemon-a/,\nhttp://daemon-a/ ",
        worker_daemon_pools: %{
          "coding-linux" => [
            %{"id" => "pool-endpoint-1", "endpoint" => "http://daemon-b/", "worker_id" => "worker-b"},
            %{"endpoint" => "http://user:secret@daemon-c/"}
          ],
          "other-pool" => [%{"endpoint" => "http://daemon-other/"}]
        }
      )

    assert [
             %{endpoint: "http://daemon-a", source: "opts.worker_daemon_endpoints"},
             %{
               endpoint: "http://daemon-b",
               endpoint_id: "pool-endpoint-1",
               worker_id: "worker-b",
               source: "opts.worker_daemon_pools.coding-linux"
             }
             | _rest
           ] = candidates
  end

  test "deduplicates candidates by endpoint while keeping first occurrence" do
    assert [
             %{endpoint: "http://daemon-a", source: "first"},
             %{endpoint: "http://daemon-b", source: "third"}
           ] =
             Candidates.unique([
               %{endpoint: "http://daemon-a", source: "first"},
               %{endpoint: "http://daemon-a", source: "second"},
               %{endpoint: "http://daemon-b", source: "third"},
               %{source: "missing-endpoint"}
             ])
  end
end
