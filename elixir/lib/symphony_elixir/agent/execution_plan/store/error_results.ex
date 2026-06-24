defmodule SymphonyElixir.Agent.ExecutionPlan.Store.ErrorResults do
  @moduledoc """
  Store operation error-result constructors.

  Machine-code strings are owned by `SymphonyElixir.Agent.ExecutionPlan.ErrorCodes`.
  This module owns the Store API's runtime error envelopes: message text and
  operation-specific details such as plan id, item id, revision, or evidence
  scope.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store, as: StoreErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes

  @spec plan_conflict(String.t()) :: map()
  def plan_conflict(plan_id) do
    %{
      code: StoreErrorCodes.plan_conflict(),
      message: "An Agent execution plan with this plan_id already exists.",
      plan_id: plan_id
    }
  end

  @spec plan_not_found(String.t() | nil) :: map()
  def plan_not_found(plan_id) do
    %{code: StoreErrorCodes.plan_not_found(), message: "Agent execution plan was not found.", plan_id: plan_id}
  end

  @spec plan_id_mismatch(String.t(), term()) :: map()
  def plan_id_mismatch(current_plan_id, replacement_plan_id) do
    %{
      code: StoreErrorCodes.plan_id_mismatch(),
      message: "Replacement plan_id must match the stored Agent execution plan.",
      current_plan_id: current_plan_id,
      replacement_plan_id: replacement_plan_id
    }
  end

  @spec revision_conflict(pos_integer(), term()) :: map()
  def revision_conflict(current_revision, expected_revision) do
    %{
      code: StoreErrorCodes.revision_conflict(),
      message: "Agent execution plan revision does not match the caller-observed revision.",
      current_revision: current_revision,
      expected_revision: expected_revision
    }
  end

  @spec revision_rollback(pos_integer(), term()) :: map()
  def revision_rollback(current_revision, replacement_revision) do
    %{
      code: StoreErrorCodes.revision_conflict(),
      message: "Replacement Agent execution plan revision must not move backwards.",
      current_revision: current_revision,
      replacement_revision: replacement_revision
    }
  end

  @spec item_update_not_allowed(String.t() | nil, String.t(), map()) :: map()
  def item_update_not_allowed(item_id, message, extra \\ %{}) do
    Map.merge(%{code: StoreErrorCodes.item_update_not_allowed(), message: message, item_id: item_id}, extra)
  end

  @spec item_not_found(String.t()) :: map()
  def item_not_found(item_id) do
    %{code: StoreErrorCodes.item_not_found(), message: "Agent execution plan item was not found.", item_id: item_id}
  end

  @spec invalid_agent_item(term()) :: map()
  def invalid_agent_item(item_id) do
    %{code: ValidationErrorCodes.schema_invalid(), message: "Agent item upsert requires item objects with item_id.", item_id: item_id}
  end

  @spec evidence_scope_mismatch(String.t(), map()) :: map()
  def evidence_scope_mismatch(evidence_id, details) do
    Map.merge(
      %{
        code: EvidenceErrorCodes.evidence_scope_mismatch(),
        message: "Evidence reference context does not match the Agent execution plan context.",
        evidence_id: evidence_id
      },
      details
    )
  end

  @spec evidence_requirements_unsatisfied(String.t(), [String.t()]) :: map()
  def evidence_requirements_unsatisfied(item_id, evidence_kinds) do
    %{
      code: EvidenceErrorCodes.evidence_requirements_unsatisfied(),
      message: "Required evidence is not satisfied for item completion.",
      item_id: item_id,
      evidence_kinds: evidence_kinds
    }
  end

  @spec store_unavailable() :: map()
  def store_unavailable do
    %{code: StoreErrorCodes.store_unavailable(), message: "Agent execution plan store is not running."}
  end
end
