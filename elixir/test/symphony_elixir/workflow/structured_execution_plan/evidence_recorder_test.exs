defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorderTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @plan_id "plan-test-1"
  @run_id "run-test-1"
  @issue_id "TES-79"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @created_at "2026-05-20T00:00:00Z"
  @enabled_gates %{Contract.enabled_gate_key() => true}

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "repo_commit completes a matching implementation item", %{store: store} do
    create_plan!(store, [item("repo.commit", "repo_commit", ["head_sha"])])

    record_tool!(store, "repo_commit", %{
      "action" => "committed",
      "headSha" => "abc123",
      "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
    })

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "repo.commit") == "complete"
    assert [ref] = item_refs(plan, "repo.commit")
    assert ref["evidence_kind"] == "repo_commit"
    assert ref["payload"]["head_sha"] == "abc123"
  end

  test "recording is controlled by the canonical structured plan gate", %{store: store} do
    create_plan!(store, [item("repo.commit", "repo_commit", ["head_sha"])])

    EvidenceRecorder.record_typed_tool_result(
      "repo",
      %{"repository" => "openai/symphony"},
      "repo_commit",
      %{"run_id" => @run_id, "issue_id" => @issue_id},
      {:success,
       %{
         "data" => %{
           "action" => "committed",
           "headSha" => "abc123",
           "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
         }
       }},
      structured_execution_plan: %{enabled: true, plan_id: @plan_id, server: store}
    )

    assert {:ok, plan_after_private_flag} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_private_flag, "repo.commit") == "pending"

    record_tool!(store, "repo_commit", %{
      "action" => "committed",
      "headSha" => "abc123",
      "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
    })

    assert {:ok, plan_after_gate} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_gate, "repo.commit") == "complete"
  end

  test "repo_push completes only when published head matches pushed head", %{store: store} do
    create_plan!(store, [item("repo.push", "repo_push", ["branch", "head_sha", "published_head_sha"])])

    record_tool!(store, "repo_push", %{
      "branch" => "feature/demo",
      "headSha" => "abc123",
      "publishedHeadSha" => "def456",
      "remote" => "origin"
    })

    assert {:ok, plan_after_mismatch} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_mismatch, "repo.push") == "pending"

    record_tool!(store, "repo_push", %{
      "branch" => "feature/demo",
      "headSha" => "abc123",
      "publishedHeadSha" => "abc123",
      "remote" => "origin"
    })

    assert {:ok, plan_after_match} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_match, "repo.push") == "complete"
    assert length(item_refs(plan_after_match, "repo.push")) == 2
  end

  test "repo_diff check=true completes a validation item", %{store: store} do
    create_plan!(store, [item("validation.diff", "repo_diff", ["check"], kind: "validation")])

    record_tool!(
      store,
      "repo_diff",
      %{
        "diffCheck" => %{"status" => "passed"},
        "status" => %{"headSha" => "abc123", "root" => "/workspace/symphony"}
      },
      arguments: %{"args" => ["--", "lib"]}
    )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "validation.diff") == "complete"
    assert get_in(item_refs(plan, "validation.diff"), [Access.at(0), "payload", "check"]) == true
  end

  test "tracker evidence recording uses workflow capability metadata instead of tracker tool names", %{store: store} do
    create_plan!(store, [item("tracker.handoff", "tracker_upsert_workpad", ["workpad_id"], kind: "handoff_record")])

    record_tool!(
      store,
      "jira_upsert_workpad",
      %{"comment" => %{"id" => "jira:issue:TES-79:workpad", "updated" => true}},
      source_kind: "tracker",
      source_context: %{kind: "jira"},
      tool_context: tool_context("jira_upsert_workpad", TrackerCapabilities.upsert_workpad())
    )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "tracker.handoff") == "complete"
    assert [ref] = item_refs(plan, "tracker.handoff")
    assert ref["evidence_kind"] == "tracker_upsert_workpad"
    assert ref["producer"] == "jira_upsert_workpad"
    assert ref["payload"]["tracker_kind"] == "tracker"
    assert ref["payload"]["workpad_id"] == "jira:issue:TES-79:workpad"
  end

  test "replayed tool results are idempotent", %{store: store} do
    create_plan!(store, [item("repo.commit", "repo_commit", ["head_sha"])])

    payload = %{
      "action" => "committed",
      "headSha" => "abc123",
      "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
    }

    record_tool!(store, "repo_commit", payload)
    assert {:ok, %{"revision" => revision_after_first} = first_plan} = Store.fetch(@plan_id, server: store)
    assert item_status(first_plan, "repo.commit") == "complete"
    assert length(item_refs(first_plan, "repo.commit")) == 1

    record_tool!(store, "repo_commit", payload, observed_at: "2026-05-20T00:00:02Z")
    assert {:ok, %{"revision" => ^revision_after_first} = replayed_plan} = Store.fetch(@plan_id, server: store)
    assert length(item_refs(replayed_plan, "repo.commit")) == 1
  end

  test "idempotency keys are stable strings independent of observed_at" do
    {:ok, [first_ref]} =
      EvidenceBinding.bind_typed_tool_result(
        "repo",
        %{"repository" => "openai/symphony"},
        "repo_commit",
        %{"run_id" => @run_id, "issue_id" => @issue_id},
        {:success,
         %{
           "data" => %{
             "action" => "committed",
             "headSha" => "abc123",
             "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
           }
         }},
        observed_at: "2026-05-20T00:00:01Z"
      )

    {:ok, [second_ref]} =
      EvidenceBinding.bind_typed_tool_result(
        "repo",
        %{"repository" => "openai/symphony"},
        "repo_commit",
        %{"run_id" => @run_id, "issue_id" => @issue_id},
        {:success,
         %{
           "data" => %{
             "action" => "committed",
             "headSha" => "abc123",
             "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "abc123"}
           }
         }},
        observed_at: "2026-05-20T00:00:02Z"
      )

    first_key = EvidenceBinding.idempotency_key(first_ref)
    second_key = EvidenceBinding.idempotency_key(second_ref)

    assert is_binary(first_key)
    assert first_key == second_key
    assert first_ref["evidence_id"] == second_ref["evidence_id"]
  end

  test "new repo evidence stales validation checks feedback and handoff items", %{store: store} do
    create_plan!(store, [
      item("repo.commit", "repo_commit", ["head_sha"]),
      item("validation.diff", "repo_diff", ["check"],
        kind: "validation",
        status: "complete",
        evidence_refs: [evidence_ref("repo_diff", %{"check" => true, "head_sha" => "old123"})]
      ),
      item("tracker.handoff", "tracker_upsert_workpad", ["workpad_id"],
        kind: "handoff_record",
        status: "complete",
        evidence_refs: [evidence_ref("tracker_upsert_workpad", %{"workpad_id" => "linear:issue:issue-1:workpad", "updated" => true})]
      )
    ])

    record_tool!(
      store,
      "repo_commit",
      %{
        "action" => "committed",
        "headSha" => "new456",
        "status" => %{"branch" => "feature/demo", "clean" => true, "headSha" => "new456"}
      },
      observed_at: "2026-05-20T00:00:05Z",
      updated_at: "2026-05-20T00:00:05Z"
    )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "repo.commit") == "complete"
    assert item_status(plan, "validation.diff") == "in_progress"
    assert item_status(plan, "tracker.handoff") == "in_progress"
  end

  test "cross-run evidence is rejected", %{store: store} do
    create_plan!(store, [item("repo.commit", "repo_commit", ["head_sha"])])

    assert {:error, %{code: "cross_run_evidence_not_allowed", evidence_run_id: "other-run"}} =
             Store.record_evidence_refs(
               @plan_id,
               [evidence_ref("repo_commit", %{"head_sha" => "abc123"}, run_id: "other-run")],
               server: store
             )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_refs(plan, "repo.commit") == []
  end

  defp record_tool!(store, tool, data, opts \\ []) do
    source_kind = Keyword.get(opts, :source_kind, "repo")
    source_context = Keyword.get(opts, :source_context, %{"repository" => "openai/symphony"})
    observed_at = Keyword.get(opts, :observed_at, "2026-05-20T00:00:01Z")
    updated_at = Keyword.get(opts, :updated_at, observed_at)

    arguments =
      %{"run_id" => @run_id, "issue_id" => @issue_id}
      |> Map.merge(Keyword.get(opts, :arguments, %{}))

    EvidenceRecorder.record_typed_tool_result(
      source_kind,
      source_context,
      tool,
      arguments,
      {:success, %{"data" => data}},
      observed_at: observed_at,
      updated_at: updated_at,
      gates: @enabled_gates,
      structured_execution_plan: %{plan_id: @plan_id, server: store},
      tool_context: Keyword.get(opts, :tool_context)
    )
  end

  defp tool_context(tool, capability) do
    %{
      tool_metadata: %{
        tool => %{
          Metadata.Contract.capability() => capability
        }
      }
    }
  end

  defp create_plan!(store, items) do
    assert {:ok, _plan} = Store.create(plan(items), server: store)
  end

  defp plan(items) do
    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => @plan_id,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "tracker_kind" => "linear",
      "workflow_profile" => @profile,
      "route_key" => "developing",
      "status" => "active",
      "items" => items,
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp item(item_id, evidence_kind, required_fields, opts \\ []) do
    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => Keyword.get(opts, :kind, "tool_evidence"),
      "status" => Keyword.get(opts, :status, "pending"),
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => evidence_kind,
          "required_fields" => required_fields,
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => Keyword.get(opts, :evidence_refs, []),
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_kind, payload, opts \\ []) do
    %{
      "evidence_id" => Keyword.get(opts, :evidence_id, "evidence-#{evidence_kind}"),
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => Keyword.get(opts, :producer, evidence_kind),
      "run_id" => Keyword.get(opts, :run_id, @run_id),
      "issue_id" => Keyword.get(opts, :issue_id, @issue_id),
      "observed_at" => Keyword.get(opts, :observed_at, "2026-05-20T00:00:01Z"),
      "payload" => payload
    }
  end

  defp item_status(plan, item_id), do: plan |> item(item_id) |> Map.fetch!("status")
  defp item_refs(plan, item_id), do: plan |> item(item_id) |> Map.fetch!("evidence_refs")

  defp item(%{"items" => items}, item_id) do
    Enum.find(items, &(Map.get(&1, "item_id") == item_id))
  end
end
