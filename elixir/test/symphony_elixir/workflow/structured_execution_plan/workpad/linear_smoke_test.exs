defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.LinearSmokeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Tracker.Linear.Adapter, as: LinearAdapter
  alias SymphonyElixir.Tracker.WorkpadRegistry
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer

  @created_at "2026-05-20T00:00:00Z"
  @gates %{
    Contract.enabled_gate_key() => true,
    Contract.render_workpad_gate_key() => true
  }

  setup do
    WorkpadRegistry.reset()
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "controlled Linear rendering smoke writes through tracker upsert workpad typed tool", %{store: store} do
    assert {:ok, _plan} = Store.create(plan(), server: store)

    test_pid = self()

    linear_client = fn query, variables, opts ->
      send(test_pid, {:linear_graphql, query, variables, opts})

      cond do
        query =~ "SymphonyLinearCreateWorkpad" ->
          assert %{issueId: "TES-79", body: body} = variables
          assert body =~ "mode=write"
          assert body =~ "repo_commit:1"
          assert body =~ "repo_diff:1"
          refute body =~ "feature/demo"
          refute body =~ "raw_provider_payload"
          refute body =~ "secret-token"
          {:ok, linear_comment_create_response(body)}

        query =~ "SymphonyLinearUpdateWorkpad" ->
          flunk("missing rendered Workpad smoke should create, not update")

        true ->
          flunk("unexpected Linear GraphQL operation")
      end
    end

    tracker_executor = fn tool, arguments, opts ->
      LinearAdapter.execute_dynamic_tool(%{}, tool, arguments, Keyword.put(opts, :linear_client, linear_client))
    end

    assert {:ok,
            %{
              "success" => true,
              "status" => "created",
              "tracker_tool" => "linear_upsert_workpad",
              "workpad" => %{"id" => "linear:issue:TES-79:workpad"},
              "plan_revision" => 1,
              "stored_plan_revision" => 1,
              "rendered_workpad" => %{
                "fingerprint" => fingerprint,
                "rendered_item_count" => 2,
                "items_truncated" => false
              }
            }} =
             Writer.write("plan-linear-smoke-1",
               gates: @gates,
               server: store,
               tracker_comments: [],
               tracker_executor: tracker_executor,
               tracker_opts: []
             )

    assert is_binary(fingerprint)

    assert_received {:linear_graphql, create_query, %{issueId: "TES-79", body: body}, []}
    assert create_query =~ "SymphonyLinearCreateWorkpad"
    assert body =~ "## Structured Execution Plan Workpad"
    assert body =~ "- [x] `repo.commit`"
    assert body =~ "- [ ] `repo.diff`"

    assert {:ok,
            %{
              "revision" => 1,
              "rendering" => %{
                "workpad_id" => "linear:issue:TES-79:workpad",
                "fingerprint" => ^fingerprint,
                "mode" => "write",
                "plan_revision" => 1,
                "tracker_kind" => "linear"
              }
            }} = Store.fetch("plan-linear-smoke-1", server: store)
  end

  defp plan do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => "plan-linear-smoke-1",
      "run_id" => "run-linear-smoke-1",
      "issue_id" => "TES-79",
      "tracker_kind" => "linear",
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "route_key" => "developing",
      "status" => "active",
      "items" => [
        item("repo.commit", "complete", [
          evidence_ref("evidence-commit", "repo_commit", %{
            "head_sha" => "abc123",
            "branch" => "feature/demo",
            "raw_provider_payload" => "must-not-render"
          })
        ]),
        item("repo.diff", "pending", [
          evidence_ref("evidence-diff", "repo_diff", %{
            "check" => true,
            "token" => "secret-token"
          })
        ])
      ],
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp item(item_id, status, evidence_refs) do
    evidence_kind =
      evidence_refs
      |> List.first(%{})
      |> Map.get("evidence_kind", "repo_commit")

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
          "evidence_kind" => evidence_kind,
          "required_fields" => [],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => evidence_refs,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_id, evidence_kind, payload) do
    %{
      "evidence_id" => evidence_id,
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => evidence_kind,
      "run_id" => "run-linear-smoke-1",
      "issue_id" => "TES-79",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => payload
    }
  end

  defp linear_comment_create_response(body) do
    %{
      "data" => %{
        "commentCreate" => %{
          "success" => true,
          "comment" => %{
            "id" => "comment-rendered",
            "body" => body,
            "url" => "https://linear.app/test/comment/comment-rendered"
          }
        }
      }
    }
  end
end
