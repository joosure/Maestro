defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBindingTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding, as: CodingPrDeliveryEvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceRecorder
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.EvidencePolicy
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @plan_id "coding-pr-delivery-plan-test-1"
  @run_id "coding-pr-delivery-run-test-1"
  @issue_id "TES-79"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @created_at "2026-05-20T00:00:00Z"
  @enabled_gates %{Contract.enabled_gate_key() => true}

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  test "contributes change-proposal evidence binding through the platform provider registry" do
    assert EvidenceBinding.evidence_kind("repo_read_change_proposal_checks") ==
             CodingPrDeliveryEvidenceBinding.repo_read_change_proposal_checks_evidence_kind()

    assert EvidenceBinding.evidence_kind("jira_attach_external_reference",
             tool_context: tool_context("jira_attach_external_reference", TrackerCapabilities.attach_external_reference())
           ) == CodingPrDeliveryEvidenceBinding.tracker_attach_change_proposal_evidence_kind()
  end

  test "fails closed for non-keyword evidence binding options" do
    malformed_opts = [:not_keyword]

    assert EvidenceBinding.evidence_kind("repo_read_change_proposal_checks", malformed_opts) == nil
    assert CodingPrDeliveryEvidenceBinding.evidence_kind("repo_read_change_proposal_checks", malformed_opts) == nil

    assert {:ok, []} =
             EvidenceBinding.bind_typed_tool_result(
               "repo_provider",
               %{},
               "repo_read_change_proposal_checks",
               %{"run_id" => @run_id, "issue_id" => @issue_id},
               {:success, %{"data" => %{"checks" => %{}}}},
               malformed_opts
             )
  end

  test "does not record empty extension evidence when critical raw payload is missing" do
    assert {:ok, []} =
             EvidenceBinding.bind_typed_tool_result(
               "repo_provider",
               %{"kind" => "github"},
               "repo_create_or_update_change_proposal",
               %{"run_id" => @run_id, "issue_id" => @issue_id},
               {:success, %{"data" => %{}}},
               []
             )

    assert {:ok, []} =
             EvidenceBinding.bind_typed_tool_result(
               "repo_provider",
               %{"kind" => "github"},
               "repo_read_change_proposal_checks",
               %{"run_id" => @run_id, "issue_id" => @issue_id},
               {:success, %{"data" => %{}}},
               []
             )

    assert {:ok, []} =
             EvidenceBinding.bind_typed_tool_result(
               "tracker",
               %{"kind" => "jira"},
               "jira_attach_external_reference",
               %{"run_id" => @run_id, "issue_id" => @issue_id, "reference_kind" => "change_proposal"},
               {:success, %{"data" => %{}}},
               tool_context: tool_context("jira_attach_external_reference", TrackerCapabilities.attach_external_reference())
             )
  end

  test "does not treat non-change-proposal external references as coding PR delivery evidence", %{store: store} do
    evidence_kind = CodingPrDeliveryEvidenceBinding.tracker_attach_change_proposal_evidence_kind()
    create_plan!(store, [item("tracker.linkage", evidence_kind, ["linked_to_tracker", "url"])])

    record_tool!(
      store,
      "jira_attach_external_reference",
      %{
        "attachment" => %{"id" => "link-1", "url" => "https://docs.example.test/architecture"},
        "externalReference" => %{"url" => "https://docs.example.test/architecture", "externalId" => "architecture"}
      },
      source_kind: "jira",
      arguments: %{"reference_kind" => "design_doc", "external_id" => "architecture", "url" => "https://docs.example.test/architecture"},
      tool_context: tool_context("jira_attach_external_reference", TrackerCapabilities.attach_external_reference())
    )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "tracker.linkage") == "pending"
  end

  test "owns change-proposal URL validity policy" do
    evidence_kind = CodingPrDeliveryEvidenceBinding.repo_create_or_update_change_proposal_evidence_kind()

    assert CodingPrDeliveryEvidenceBinding.allowed_change_proposal_url_schemes() == ~w(http https)

    assert EvidencePolicy.valid?(evidence_kind, %{
             Evidence.url_key() => "https://github.com/acme/repo/pull/12"
           })

    refute EvidencePolicy.valid?(evidence_kind, %{
             Evidence.url_key() => "ftp://github.com/acme/repo/pull/12"
           })

    refute EvidencePolicy.valid?(evidence_kind, %{
             Evidence.url_key() => "https://github.com/acme/repo/compare/main...feature"
           })
  end

  test "change proposal creation requires a provider-native URL", %{store: store} do
    evidence_kind = CodingPrDeliveryEvidenceBinding.repo_create_or_update_change_proposal_evidence_kind()
    create_plan!(store, [item("repo.change_proposal", evidence_kind, ["url", "number"])])

    record_tool!(
      store,
      "repo_create_or_update_change_proposal",
      %{
        "action" => "created",
        "changeProposal" => %{
          "provider" => "github",
          "repository" => "openai/symphony",
          "number" => 122,
          "url" => "https://github.com/openai/symphony/compare/main...feature/demo"
        }
      },
      source_kind: "repo_provider",
      source_context: %{"kind" => "github"}
    )

    assert {:ok, plan_after_compare_url} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_compare_url, "repo.change_proposal") == "pending"

    record_tool!(
      store,
      "repo_create_or_update_change_proposal",
      %{
        "action" => "created",
        "changeProposal" => %{
          "provider" => "github",
          "repository" => "openai/symphony",
          "number" => 122,
          "url" => "https://github.com/openai/symphony/pull/122"
        }
      },
      source_kind: "repo_provider",
      source_context: %{"kind" => "github"},
      observed_at: "2026-05-20T00:00:02Z",
      updated_at: "2026-05-20T00:00:02Z"
    )

    assert {:ok, plan_after_pr_url} = Store.fetch(@plan_id, server: store)
    assert item_status(plan_after_pr_url, "repo.change_proposal") == "complete"
  end

  test "checks and discussion evidence update matching items", %{store: store} do
    checks_kind = CodingPrDeliveryEvidenceBinding.repo_read_change_proposal_checks_evidence_kind()
    discussion_kind = CodingPrDeliveryEvidenceBinding.repo_read_change_proposal_discussion_evidence_kind()

    create_plan!(store, [
      item("repo.checks", checks_kind, ["status"], kind: "validation"),
      item("repo.feedback", discussion_kind, ["status"], kind: "validation")
    ])

    record_tool!(
      store,
      "repo_read_change_proposal_checks",
      %{"checks" => %{"runs" => [%{"bucket" => "passed"}], "headSha" => "abc123"}},
      source_kind: "repo_provider"
    )

    record_tool!(
      store,
      "repo_read_change_proposal_discussion",
      %{"discussion" => %{"summary" => %{"actionableFeedbackCount" => 0}}},
      source_kind: "repo_provider",
      observed_at: "2026-05-20T00:00:02Z",
      updated_at: "2026-05-20T00:00:02Z"
    )

    assert {:ok, plan} = Store.fetch(@plan_id, server: store)
    assert item_status(plan, "repo.checks") == "complete"
    assert item_status(plan, "repo.feedback") == "complete"
  end

  test "checks evidence binding keeps empty provider checks unavailable" do
    assert {:ok, [ref]} =
             EvidenceBinding.bind_typed_tool_result(
               "repo_provider",
               %{"repository" => "openai/symphony"},
               "repo_read_change_proposal_checks",
               %{"run_id" => @run_id, "issue_id" => @issue_id},
               {:success, %{"data" => %{"checks" => %{"runs" => [], "summary" => %{}}}}},
               observed_at: "2026-05-20T00:00:02Z"
             )

    assert ref["payload"]["status"] == "unavailable"
    assert ref["payload"]["run_count"] == 0
  end

  test "new repo evidence stales extension-owned validation evidence", %{store: store} do
    checks_kind = CodingPrDeliveryEvidenceBinding.repo_read_change_proposal_checks_evidence_kind()
    discussion_kind = CodingPrDeliveryEvidenceBinding.repo_read_change_proposal_discussion_evidence_kind()

    create_plan!(store, [
      item("repo.commit", "repo_commit", ["head_sha"]),
      item("repo.checks", checks_kind, ["status"],
        kind: "validation",
        status: "complete",
        evidence_refs: [evidence_ref(checks_kind, %{"status" => "passed", "head_sha" => "old123"})]
      ),
      item("repo.feedback", discussion_kind, ["status"],
        kind: "validation",
        status: "complete",
        evidence_refs: [evidence_ref(discussion_kind, %{"status" => "clear"})]
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
    assert item_status(plan, "repo.checks") == "in_progress"
    assert item_status(plan, "repo.feedback") == "in_progress"
  end

  defp record_tool!(store, tool, data, opts) do
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

  defp item(%{"items" => items}, item_id) do
    Enum.find(items, &(Map.get(&1, "item_id") == item_id))
  end
end
