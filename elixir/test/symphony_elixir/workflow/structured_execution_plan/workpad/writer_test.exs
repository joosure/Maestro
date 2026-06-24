defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.WriterTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer

  @created_at "2026-05-20T00:00:00Z"
  @gates %{
    Contract.enabled_gate_key() => true,
    Contract.render_workpad_gate_key() => true
  }

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "default gate-off behavior skips without touching store or tracker" do
    executor = fn _tool, _args, _opts -> flunk("tracker Workpad executor must not be called when the gate is off") end

    assert {:ok,
            %{
              "success" => true,
              "status" => "skipped",
              "reason" => "render_workpad_gate_disabled"
            }} = Writer.write("missing-plan", tracker_executor: executor)
  end

  test "missing rendered Workpad is created through tracker upsert and marker is recorded", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([item("repo.commit", "pending")]), server: store)
    test_pid = self()

    executor = fn tool, args, opts ->
      send(test_pid, {:tracker_write, tool, args, opts})

      {:success,
       %{
         "data" => %{
           "comment" => %{
             "id" => "linear:issue:TES-79:workpad",
             "provider_ref" => %{"type" => "comment", "id" => "comment-new"},
             "created" => true,
             "body" => args["body"],
             "url" => "https://linear.app/test/comment/comment-new"
           }
         },
         "warnings" => []
       }}
    end

    assert {:ok,
            %{
              "success" => true,
              "status" => "created",
              "workpad" => %{"id" => "linear:issue:TES-79:workpad"},
              "stored_plan_revision" => 1,
              "workpad_state" => %{"state" => "missing"}
            }} =
             Writer.write("plan-test-1",
               gates: @gates,
               server: store,
               tracker_comments: [],
               tracker_executor: executor
             )

    assert_received {:tracker_write, "linear_upsert_workpad", args, []}
    assert args["issue_id"] == "TES-79"
    assert args["heading"] == "Structured Execution Plan Workpad"
    assert args["mode"] == "replace"
    refute Map.has_key?(args, "comment_id")
    refute Map.has_key?(args, "workpad_id")
    assert args["body"] =~ "mode=write"
    assert args["body"] =~ "- [ ] `repo.commit`"

    assert {:ok, %{"revision" => 1, "rendering" => marker}} = Store.fetch("plan-test-1", server: store)
    assert marker["workpad_id"] == "linear:issue:TES-79:workpad"
    assert marker["mode"] == "write"
    assert marker["plan_revision"] == 1
    refute Map.has_key?(marker, "body")
  end

  test "known rendered Workpad updates by workpad id without inspecting tracker comment bodies", %{store: store} do
    base_plan = plan([item("repo.commit", "pending")])
    assert {:ok, _plan} = Store.create(base_plan, server: store)
    assert {:ok, old_render} = Renderer.render(base_plan, mode: "write")

    assert {:ok, _plan} =
             Store.record_render_marker(
               "plan-test-1",
               Map.put(old_render["marker"], "workpad_id", "linear:issue:TES-79:workpad"),
               1,
               server: store
             )

    assert {:ok, %{"revision" => 2}} =
             Store.update_item_status("plan-test-1", "repo.commit", "in_progress", 1, server: store)

    test_pid = self()

    executor = fn tool, args, _opts ->
      send(test_pid, {:tracker_write, tool, args})

      {:success,
       %{
         "data" => %{
           "comment" => %{
             "id" => "linear:issue:TES-79:workpad",
             "provider_ref" => %{"type" => "comment", "id" => "comment-1"},
             "updated" => true,
             "body" => args["body"]
           }
         }
       }}
    end

    assert {:ok,
            %{
              "status" => "updated",
              "workpad" => %{"id" => "linear:issue:TES-79:workpad"},
              "plan_revision" => 2,
              "workpad_state" => %{"state" => "known", "workpad_id" => "linear:issue:TES-79:workpad"}
            }} =
             Writer.write("plan-test-1",
               gates: @gates,
               server: store,
               tracker_comments: [%{"id" => "comment-1", "body" => old_render["body"] <> "\nmanual note ignored\n"}],
               tracker_executor: executor
             )

    assert_received {:tracker_write, "linear_upsert_workpad", %{"workpad_id" => "linear:issue:TES-79:workpad"}}

    assert {:ok, %{"revision" => 2, "rendering" => %{"plan_revision" => 2, "workpad_id" => "linear:issue:TES-79:workpad"}}} =
             Store.fetch("plan-test-1", server: store)
  end

  test "tracker write failures return bounded errors and do not record marker", %{store: store} do
    assert {:ok, _plan} = Store.create(plan([item("repo.commit", "pending")]), server: store)

    executor = fn _tool, _args, _opts ->
      {:failure, %{"error" => %{"code" => "provider_error", "message" => "write failed", "raw" => "hidden"}}}
    end

    assert {:error, %{code: "rendering_failed", details: %{"tracker_result" => %{"error" => %{"code" => "provider_error"}}}}} =
             Writer.write("plan-test-1",
               gates: @gates,
               server: store,
               tracker_comments: [],
               tracker_executor: executor
             )

    assert {:ok, stored_plan} = Store.fetch("plan-test-1", server: store)
    refute Map.has_key?(stored_plan, "rendering")
  end

  test "default tracker tool is resolved from tracker capability specs", %{store: store} do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"custom" => __MODULE__.CustomTrackerAdapter})
    on_exit(fn -> Application.delete_env(:symphony_elixir, :tracker_adapters) end)

    assert {:ok, _plan} = Store.create(plan([item("repo.commit", "pending")]) |> Map.put("tracker_kind", "custom"), server: store)

    test_pid = self()

    executor = fn tool, args, _opts ->
      send(test_pid, {:tracker_write, tool, args})

      {:success,
       %{
         "comment" => %{
           "id" => "custom:issue:TES-79:workpad",
           "created" => true,
           "body" => args["body"]
         }
       }}
    end

    assert {:ok, %{"status" => "created", "tracker_tool" => "custom_upsert_workpad"}} =
             Writer.write("plan-test-1",
               gates: @gates,
               server: store,
               tracker_executor: executor
             )

    assert_received {:tracker_write, "custom_upsert_workpad", %{"issue_id" => "TES-79", "mode" => "replace"}}
  end

  test "public writer facade keeps tracker-specific names behind the tracker boundary" do
    writer_source =
      "lib/symphony_elixir/workflow/structured_execution_plan/workpad/writer.ex"
      |> Path.expand(File.cwd!())
      |> File.read!()

    refute writer_source =~ "linear_upsert_workpad"
    refute writer_source =~ "tapd_upsert_workpad"
    refute writer_source =~ ~r/default_tracker_tool\(\"linear\"/
    refute writer_source =~ ~r/default_tracker_tool\(\"tapd\"/
  end

  defp plan(items) do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-test-1",
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "tracker_kind" => "linear",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => items,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp item(item_id, status) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => "tool_evidence",
      "status" => status,
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "repo_commit",
          "required_fields" => ["head_sha"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => [],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defmodule CustomTrackerAdapter do
    @moduledoc false

    alias SymphonyElixir.Agent.DynamicTool.Metadata
    alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities

    @spec dynamic_tools(map()) :: [map()]
    def dynamic_tools(_tracker) do
      [
        %{
          "name" => "custom_upsert_workpad",
          Metadata.Contract.capability() => TrackerCapabilities.upsert_workpad()
        }
      ]
    end
  end
end
