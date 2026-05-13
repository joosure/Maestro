defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.SelectionTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.Selection
  alias SymphonyWorkerDaemon.Protocol

  test "projects target metadata for a selected candidate" do
    target =
      Target.new(
        placement: :worker_daemon,
        worker_pool: "coding-linux",
        workspace_path: "/work",
        metadata: %{worker_daemon_worker_id: "worker-pinned"}
      )

    selected = Selection.target_for_candidate(target, %{endpoint: "http://daemon-a", worker_id: "worker-candidate"})

    assert selected.metadata.worker_daemon_endpoint == "http://daemon-a"
    assert selected.metadata.worker_daemon_worker_id == "worker-pinned"
  end

  test "projects successful selection without secret-shaped fields" do
    health = %{
      status: "ready",
      protocol_version: Protocol.protocol_version(),
      worker_id: "worker-a",
      daemon_instance_id: "daemon-a",
      features: ["session_create"],
      token: "secret-token"
    }

    assert %{
             endpoint: "http://daemon-a",
             worker_id: "worker-a",
             daemon_instance_id: "daemon-a",
             endpoint_id: "endpoint-a",
             source: "opts.worker_daemon_endpoints",
             health_source: "preflight",
             health: safe_health
           } =
             Selection.success(
               %{endpoint: "http://daemon-a", endpoint_id: "endpoint-a", source: "opts.worker_daemon_endpoints"},
               health,
               "preflight"
             )

    refute Map.has_key?(safe_health, :token)
    assert safe_health.status == "ready"
  end

  test "projects structured failure reasons" do
    assert %{
             endpoint: "http://daemon-a",
             worker_id: "worker-a",
             reason: %{code: "worker_daemon_missing_features", features: ["session_events"]}
           } =
             Selection.failure(
               %{endpoint: "http://daemon-a", worker_id: "worker-a"},
               {:worker_daemon_missing_features, [:session_events]}
             )
  end
end
