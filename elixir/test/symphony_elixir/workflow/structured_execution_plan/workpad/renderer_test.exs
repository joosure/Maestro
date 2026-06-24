defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.RendererTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer

  @created_at "2026-05-20T00:00:00Z"

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "renders deterministic Markdown for the same canonical plan" do
    plan = plan([item("repo.commit", "Commit implementation", "complete")])

    assert {:ok, first} = Renderer.render(plan)
    assert {:ok, second} = Renderer.render(plan)

    assert first == second
    assert first["body"] =~ "## Structured Execution Plan Workpad"
    assert first["body"] =~ "symphony:structured_execution_plan:v1"
    assert first["fingerprint"] == first["marker"]["fingerprint"]
  end

  test "checkbox state comes only from item status" do
    plan =
      plan([
        item("item.complete", "Complete item", "complete"),
        item("item.skipped", "Skipped item", "skipped"),
        item("item.pending", "Pending item", "pending"),
        item("item.progress", "Progress item", "in_progress"),
        item("item.blocked", "Blocked item", "blocked"),
        item("item.failed", "Failed item", "failed")
      ])

    assert {:ok, %{"body" => body}} = Renderer.render(plan)

    assert body =~ "- [x] `item.complete`"
    assert body =~ "- [x] `item.skipped`"
    assert body =~ "- [ ] `item.pending`"
    assert body =~ "- [ ] `item.progress`"
    assert body =~ "- [ ] `item.blocked`"
    assert body =~ "- [ ] `item.failed`"
  end

  test "raw evidence payload fields and secret-like values are not rendered" do
    plan =
      plan([
        item("repo.push", "Publish branch", "complete",
          evidence_refs: [
            evidence_ref("repo_push", %{
              "head_sha" => "abc123",
              "raw_provider_payload" => "must-not-render",
              "token" => "super-secret-token"
            })
          ]
        )
      ])

    assert {:ok, %{"body" => body}} = Renderer.render(plan)

    assert body =~ "repo_push:1"
    refute body =~ "must-not-render"
    refute body =~ "super-secret-token"
    refute body =~ "raw_provider_payload"
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

  defp item(item_id, title, status, opts \\ []) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => title,
      "kind" => "tool_evidence",
      "status" => status,
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => "repo_push",
          "required_fields" => ["head_sha"],
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => Keyword.get(opts, :evidence_refs, []),
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_kind, payload) do
    %{
      "evidence_id" => "evidence-test-#{evidence_kind}",
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => evidence_kind,
      "run_id" => "run-test-1",
      "issue_id" => "TES-79",
      "observed_at" => "2026-05-20T00:00:01Z",
      "payload" => payload
    }
  end
end
