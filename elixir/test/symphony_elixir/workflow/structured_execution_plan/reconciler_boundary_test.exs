defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ReconcilerBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.EvidencePolicy

  @observed_old "2026-05-20T00:00:01Z"
  @observed_new "2026-05-20T00:00:05Z"

  test "invalid canonical plan shape returns the shared schema validation code" do
    assert {:error, %{code: code}} = Reconciler.reconcile(%{AgentFields.items() => :not_items})
    assert code == ValidationErrorCodes.schema_invalid()

    assert {:error, %{code: code}} = Reconciler.reconcile(:not_a_plan)
    assert code == ValidationErrorCodes.schema_invalid()
  end

  test "matching canonical evidence completes a requirement-bound item" do
    repo_push = ToolMap.repo_push_evidence_kind()

    plan = %{
      AgentFields.items() => [
        item("repo.push", repo_push, [Evidence.head_sha_key(), Evidence.published_head_sha_key()],
          evidence_refs: [
            evidence_ref(repo_push, %{
              Evidence.head_sha_key() => "abc123",
              Evidence.published_head_sha_key() => "abc123"
            })
          ]
        )
      ]
    }

    assert {:ok, reconciled} = Reconciler.reconcile(plan)
    assert [reconciled_item] = Map.fetch!(reconciled, AgentFields.items())
    assert Map.fetch!(reconciled_item, AgentFields.status()) == AgentContract.complete_item_status()
  end

  test "new repo evidence marks stale validation evidence in progress" do
    repo_commit = ToolMap.repo_commit_evidence_kind()
    repo_diff = ToolMap.repo_diff_evidence_kind()

    plan = %{
      AgentFields.items() => [
        item("repo.commit", repo_commit, [Evidence.head_sha_key()],
          status: AgentContract.complete_item_status(),
          evidence_refs: [evidence_ref(repo_commit, %{Evidence.head_sha_key() => "new456"}, observed_at: @observed_new)]
        ),
        item("validation.diff", repo_diff, [EvidencePolicy.diff_check_key()],
          status: AgentContract.complete_item_status(),
          evidence_refs: [
            evidence_ref(repo_diff, %{EvidencePolicy.diff_check_key() => true}, observed_at: @observed_old)
          ]
        )
      ]
    }

    assert {:ok, reconciled} = Reconciler.reconcile(plan)
    assert [_, diff_item] = Map.fetch!(reconciled, AgentFields.items())
    assert Map.fetch!(diff_item, AgentFields.status()) == AgentContract.in_progress_item_status()
  end

  test "terminal item status is not reconciled again" do
    repo_diff = ToolMap.repo_diff_evidence_kind()

    plan = %{
      AgentFields.items() => [
        item("validation.diff", repo_diff, [EvidencePolicy.diff_check_key()],
          status: AgentContract.superseded_item_status(),
          evidence_refs: [evidence_ref(repo_diff, %{EvidencePolicy.diff_check_key() => true})]
        )
      ]
    }

    assert {:ok, reconciled} = Reconciler.reconcile(plan)
    assert [reconciled_item] = Map.fetch!(reconciled, AgentFields.items())
    assert Map.fetch!(reconciled_item, AgentFields.status()) == AgentContract.superseded_item_status()
  end

  defp item(item_id, evidence_kind, required_fields, opts) do
    %{
      AgentFields.item_id() => item_id,
      AgentFields.status() => Keyword.get(opts, :status, AgentContract.pending_item_status()),
      AgentFields.evidence_requirements() => [
        %{
          AgentFields.evidence_kind() => evidence_kind,
          AgentFields.required_fields() => required_fields,
          AgentFields.trust_classes() => [AgentContract.tool_generated_trust_class()]
        }
      ],
      AgentFields.evidence_refs() => Keyword.get(opts, :evidence_refs, [])
    }
  end

  defp evidence_ref(evidence_kind, payload, opts \\ []) do
    %{
      AgentFields.evidence_kind() => evidence_kind,
      AgentFields.source() => AgentContract.tool_generated_trust_class(),
      AgentFields.producer() => evidence_kind,
      AgentFields.observed_at() => Keyword.get(opts, :observed_at, @observed_old),
      AgentFields.payload() => payload
    }
  end
end
