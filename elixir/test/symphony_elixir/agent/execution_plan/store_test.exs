defmodule SymphonyElixir.Agent.ExecutionPlan.StoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Store
  alias SymphonyElixir.Agent.ExecutionPlan.Store.Command.Create

  @timestamp "2026-05-20T00:00:00Z"

  defmodule CaptureServer do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)
    def init(owner), do: {:ok, owner}

    def handle_call(message, _from, owner) do
      send(owner, {:store_message, message})
      {:reply, {:ok, :captured}, owner}
    end
  end

  defmodule UnavailableStore do
    @moduledoc false
  end

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "creates and fetches generic Agent execution plans", %{store: store} do
    plan = minimal_plan()

    assert {:ok, ^plan} = Store.create(plan, server: store, now: @timestamp)
    assert {:ok, ^plan} = Store.fetch("plan-agent-1", server: store)
  end

  test "deletes a single generic plan without resetting the store", %{store: store} do
    other_plan = minimal_plan() |> Map.put("plan_id", "plan-agent-2")

    assert {:ok, _plan} = Store.create(minimal_plan(), server: store, now: @timestamp)
    assert {:ok, _plan} = Store.create(other_plan, server: store, now: @timestamp)

    assert :ok = Store.delete("plan-agent-1", server: store)
    assert {:error, %{code: "plan_not_found"}} = Store.fetch("plan-agent-1", server: store)
    assert {:ok, ^other_plan} = Store.fetch("plan-agent-2", server: store)
  end

  test "facade calls report unavailable stores as error tuples" do
    unavailable_store = __MODULE__.UnavailableStore

    assert {:error, %{code: "store_unavailable"}} = Store.create(minimal_plan(), server: unavailable_store)
    assert {:error, %{code: "store_unavailable"}} = Store.fetch("plan-agent-1", server: unavailable_store)
    assert {:error, %{code: "store_unavailable"}} = Store.delete("plan-agent-1", server: unavailable_store)
    assert {:error, %{code: "store_unavailable"}} = Store.reset(server: unavailable_store)
  end

  test "facade keeps client routing opts out of command opts" do
    {:ok, capture_server} = CaptureServer.start_link(self())

    assert {:ok, :captured} = Store.create(minimal_plan(), server: capture_server, now: @timestamp)

    assert_receive {:store_message, %Create{opts: opts}}
    assert opts == [now: @timestamp]
    refute Keyword.has_key?(opts, :server)
  end

  test "rejects workflow adoption fields at the store boundary", %{store: store} do
    plan =
      minimal_plan()
      |> Map.merge(%{
        "issue_id" => "TES-1",
        "tracker_kind" => "linear",
        "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
        "route_key" => "developing"
      })

    assert {:error, %{code: "schema_invalid", errors: errors}} = Store.create(plan, server: store)
    assert Enum.any?(errors, &(&1.code == "unknown_key" and &1.path == ["issue_id"]))
  end

  test "updates item status with optimistic concurrency", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:ok, %{"revision" => 2, "items" => [%{"status" => "in_progress"}]}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "in_progress", 1, server: store)

    assert {:error, %{code: "revision_conflict", current_revision: 2, expected_revision: 1}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "complete", 1, server: store)
  end

  test "replace does not allow revision rollback", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)
    assert {:ok, %{"revision" => 2} = updated_plan} = Store.update_plan_status("plan-agent-1", "blocked", 1, server: store)

    replacement = Map.put(updated_plan, "revision", 1)

    assert {:error, %{code: "revision_conflict", current_revision: 2, replacement_revision: 1}} =
             Store.replace("plan-agent-1", replacement, 2, server: store)
  end

  test "appends immutable generic evidence refs", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    assert {:ok, %{"revision" => 2, "items" => [%{"evidence_refs" => [ref]}]}} =
             Store.append_evidence_ref("plan-agent-1", "agent.plan", evidence_ref(), 1, server: store)

    assert ref == evidence_ref()

    changed_ref = put_in(evidence_ref(), ["payload", "head_sha"], "def456")

    assert {:error, %{code: "evidence_ref_conflict", evidence_id: "evidence-agent-1"}} =
             Store.append_evidence_ref("plan-agent-1", "agent.plan", changed_ref, 2, server: store)
  end

  test "upserts only agent-draft informational items", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store)

    item = agent_item("agent.follow_up")

    assert {:ok, %{"revision" => 2, "items" => [_existing, %{"item_id" => "agent.follow_up"}]}} =
             Store.upsert_agent_items("plan-agent-1", [item], 1, server: store)

    rejected_item = Map.put(item, "source", "runtime_reconciliation")

    assert {:error, %{code: "item_update_not_allowed", item_id: "agent.follow_up"}} =
             Store.upsert_agent_items("plan-agent-1", [rejected_item], 2, server: store)
  end

  test "create and replace assign backend revisions and timestamps by default", %{store: store} do
    caller_plan =
      minimal_plan()
      |> Map.put("revision", 99)
      |> Map.put("created_at", "2026-01-01T00:00:00Z")
      |> Map.put("updated_at", "2026-01-01T00:00:00Z")

    assert {:ok, %{"revision" => 1, "created_at" => @timestamp, "updated_at" => @timestamp}} =
             Store.create(caller_plan, server: store, now: @timestamp)

    replacement =
      caller_plan
      |> Map.put("status", "blocked")
      |> Map.put("revision", 42)

    assert {:ok, %{"revision" => 2, "status" => "blocked", "created_at" => @timestamp, "updated_at" => "2026-05-20T00:00:01Z"}} =
             Store.replace("plan-agent-1", replacement, 1, server: store, now: "2026-05-20T00:00:01Z")
  end

  test "completion requires satisfied dependencies", %{store: store} do
    dependent = agent_item("agent.plan") |> Map.put("depends_on", ["agent.dep"])
    dependency = agent_item("agent.dep")
    plan = minimal_plan() |> Map.put("items", [dependent, dependency])

    assert {:ok, _plan} = Store.create(plan, server: store, now: @timestamp)

    assert {:error, %{code: "item_update_not_allowed"}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "complete", 1, server: store, now: @timestamp)

    assert {:ok, %{"revision" => 2}} =
             Store.update_item_status("plan-agent-1", "agent.dep", "complete", 1, server: store, now: @timestamp)

    assert {:ok, %{"revision" => 3, "items" => [%{"status" => "complete"}, %{"status" => "complete"}]}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "complete", 2, server: store, now: @timestamp)
  end

  test "completion requires matching trusted evidence for evidence-bound items", %{store: store} do
    item =
      agent_item("policy.check")
      |> Map.merge(%{
        "required" => true,
        "criticality" => "policy_required",
        "owned_by" => "policy",
        "source" => "policy_skeleton",
        "evidence_requirements" => [
          %{
            "evidence_kind" => "validation_result",
            "required" => true,
            "required_fields" => ["ok"],
            "trust_classes" => ["tool_generated"]
          }
        ]
      })

    assert {:ok, _plan} = Store.create(minimal_plan() |> Map.put("items", [item]), server: store, now: @timestamp)

    assert {:error, %{code: "evidence_requirements_unsatisfied", evidence_kinds: ["validation_result"]}} =
             Store.update_item_status("plan-agent-1", "policy.check", "complete", 1, server: store, now: @timestamp)

    assert {:ok, %{"revision" => 2}} =
             Store.append_evidence_ref("plan-agent-1", "policy.check", put_in(evidence_ref(), ["payload"], %{"ok" => true}), 1,
               server: store,
               now: @timestamp
             )

    assert {:ok, %{"revision" => 3, "items" => [%{"status" => "complete"}]}} =
             Store.update_item_status("plan-agent-1", "policy.check", "complete", 2, server: store, now: @timestamp)
  end

  test "evidence refs must match plan context when scoped", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store, now: @timestamp)

    scoped_ref = Map.put(evidence_ref(), "run_id", "other-run")

    assert {:error, %{code: "evidence_scope_mismatch", expected_run_id: "run-agent-1", observed_run_id: "other-run"}} =
             Store.append_evidence_ref("plan-agent-1", "agent.plan", scoped_ref, 1, server: store, now: @timestamp)
  end

  test "blocked skipped and failed item statuses require bounded status reasons", %{store: store} do
    assert {:ok, _plan} = Store.create(minimal_plan(), server: store, now: @timestamp)

    assert {:error, %{code: "item_update_not_allowed"}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "blocked", 1, server: store, now: @timestamp)

    reason = %{"reason_code" => "waiting_for_operator", "message" => "Need input."}

    assert {:ok, %{"items" => [%{"status" => "blocked", "status_reason" => ^reason}]}} =
             Store.update_item_status("plan-agent-1", "agent.plan", "blocked", 1,
               server: store,
               now: @timestamp,
               status_reason: reason
             )
  end

  defp minimal_plan do
    %{
      "schema" => "agent.execution_plan.v1",
      "plan_id" => "plan-agent-1",
      "context" => %{
        "context_kind" => "agent_run",
        "workspace_id" => "workspace-1",
        "run_id" => "run-agent-1",
        "source" => "agent",
        "mode" => "execution"
      },
      "status" => "active",
      "items" => [agent_item("agent.plan")],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp agent_item(item_id) do
    %{
      "item_id" => item_id,
      "title" => "Track execution progress",
      "kind" => "agent_step",
      "status" => "pending",
      "required" => false,
      "criticality" => "informational",
      "owned_by" => "agent",
      "source" => "agent_draft",
      "depends_on" => [],
      "evidence_requirements" => [],
      "evidence_refs" => [],
      "created_at" => "2026-05-20T00:00:00Z",
      "updated_at" => "2026-05-20T00:00:00Z",
      "revision" => 1
    }
  end

  defp evidence_ref do
    %{
      "evidence_id" => "evidence-agent-1",
      "evidence_kind" => "validation_result",
      "source" => "tool_generated",
      "producer" => "repo_diff",
      "run_id" => "run-agent-1",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => %{"head_sha" => "abc123"}
    }
  end
end
