defmodule SymphonyElixir.Agent.ExecutionPlan.Record do
  @moduledoc """
  Stable internal records for canonical `agent.execution_plan.v1` data.

  Public APIs and storage payloads remain canonical string-key maps. Store and
  domain-rule modules use these structs after schema validation so internal code
  has one stable shape.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Context
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.EvidenceRequirement
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Item
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Matcher
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Plan
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Rendering
  alias SymphonyElixir.Agent.ExecutionPlan.Record.RepoRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.SourcePlanRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.StatusReason
  alias SymphonyElixir.Agent.ExecutionPlan.Record.TrackerRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.WorkflowRef

  @spec from_map(map()) :: Plan.t()
  def from_map(plan) when is_map(plan) do
    %Plan{
      schema: Map.fetch!(plan, Fields.schema()),
      plan_id: Map.fetch!(plan, Fields.plan_id()),
      context: Context.from_map(Map.fetch!(plan, Fields.context())),
      status: Map.fetch!(plan, Fields.status()),
      items: plan |> Map.fetch!(Fields.items()) |> Enum.map(&Item.from_map/1),
      source_plan_ref: SourcePlanRef.from_map(Map.get(plan, Fields.source_plan_ref())),
      rendering: Rendering.from_map(Map.get(plan, Fields.rendering())),
      extensions: Extensions.from_map(Map.get(plan, Fields.extensions())),
      created_at: Map.fetch!(plan, Fields.created_at()),
      updated_at: Map.fetch!(plan, Fields.updated_at()),
      revision: Map.fetch!(plan, Fields.revision())
    }
  end

  @spec to_map(
          Plan.t()
          | Item.t()
          | EvidenceRef.t()
          | EvidenceRequirement.t()
          | Context.t()
          | WorkflowRef.t()
          | RepoRef.t()
          | TrackerRef.t()
          | SourcePlanRef.t()
          | Rendering.t()
          | StatusReason.t()
          | Matcher.t()
          | Extensions.t()
        ) :: map()
  def to_map(%Plan{} = plan) do
    %{
      Fields.schema() => plan.schema,
      Fields.plan_id() => plan.plan_id,
      Fields.context() => to_map(plan.context),
      Fields.status() => plan.status,
      Fields.items() => Enum.map(plan.items, &to_map/1),
      Fields.created_at() => plan.created_at,
      Fields.updated_at() => plan.updated_at,
      Fields.revision() => plan.revision
    }
    |> put_optional(Fields.source_plan_ref(), ref_to_map(plan.source_plan_ref))
    |> put_optional(Fields.rendering(), ref_to_map(plan.rendering))
    |> put_optional(Fields.extensions(), ref_to_map(plan.extensions))
  end

  def to_map(%Context{} = context) do
    %{
      Fields.context_kind() => context.context_kind,
      Fields.workspace_id() => context.workspace_id,
      Fields.run_id() => context.run_id,
      Fields.source() => context.source,
      Fields.mode() => context.mode
    }
    |> put_optional(Fields.tenant_id(), context.tenant_id)
    |> put_optional(Fields.agent_session_id(), context.agent_session_id)
    |> put_optional(Fields.task_id(), context.task_id)
    |> put_optional(Fields.recipe_run_id(), context.recipe_run_id)
    |> put_optional(Fields.workflow_ref(), ref_to_map(context.workflow_ref))
    |> put_optional(Fields.repo_ref(), ref_to_map(context.repo_ref))
    |> put_optional(Fields.tracker_ref(), ref_to_map(context.tracker_ref))
    |> put_optional(Fields.policy_refs(), context.policy_refs)
    |> put_optional(Fields.extensions(), ref_to_map(context.extensions))
  end

  def to_map(%WorkflowRef{} = ref) do
    %{}
    |> put_optional(Fields.profile_kind(), ref.profile_kind)
    |> put_optional(Fields.profile_version(), ref.profile_version)
    |> put_optional(Fields.route_key(), ref.route_key)
    |> put_optional(Fields.lifecycle_phase(), ref.lifecycle_phase)
    |> put_optional(Fields.issue_id(), ref.issue_id)
    |> put_optional(Fields.issue_identifier(), ref.issue_identifier)
    |> put_optional(Fields.tracker_kind(), ref.tracker_kind)
  end

  def to_map(%SourcePlanRef{} = ref) do
    %{
      Fields.artifact_id() => ref.artifact_id,
      Fields.hash() => ref.hash
    }
    |> put_optional(Fields.extensions(), ref_to_map(ref.extensions))
  end

  def to_map(%Rendering{} = rendering), do: rendering.value
  def to_map(%Matcher{} = matcher), do: matcher.value
  def to_map(%Extensions{} = extensions), do: extensions.value

  def to_map(%StatusReason{} = reason) do
    %{
      Fields.reason_code() => reason.reason_code
    }
    |> put_optional(Fields.actor(), reason.actor)
    |> put_optional(Fields.evidence_id(), reason.evidence_id)
    |> put_optional(Fields.message(), reason.message)
    |> put_optional(Fields.extensions(), ref_to_map(reason.extensions))
  end

  def to_map(%RepoRef{} = ref) do
    %{}
    |> put_optional(Fields.provider(), ref.provider)
    |> put_optional(Fields.repository_id(), ref.repository_id)
    |> put_optional(Fields.branch(), ref.branch)
  end

  def to_map(%TrackerRef{} = ref) do
    %{}
    |> put_optional(Fields.tracker_kind(), ref.tracker_kind)
    |> put_optional(Fields.issue_id(), ref.issue_id)
    |> put_optional(Fields.issue_identifier(), ref.issue_identifier)
  end

  def to_map(%Item{} = item) do
    %{
      Fields.item_id() => item.item_id,
      Fields.title() => item.title,
      Fields.kind() => item.kind,
      Fields.status() => item.status,
      Fields.required() => item.required,
      Fields.criticality() => item.criticality,
      Fields.owned_by() => item.owned_by,
      Fields.source() => item.source,
      Fields.depends_on() => item.depends_on,
      Fields.evidence_requirements() => Enum.map(item.evidence_requirements, &to_map/1),
      Fields.evidence_refs() => Enum.map(item.evidence_refs, &to_map/1),
      Fields.created_at() => item.created_at,
      Fields.updated_at() => item.updated_at,
      Fields.revision() => item.revision
    }
    |> put_optional(Fields.parent_item_id(), item.parent_item_id)
    |> put_optional(Fields.status_reason(), ref_to_map(item.status_reason))
    |> put_optional(Fields.extensions(), ref_to_map(item.extensions))
  end

  def to_map(%EvidenceRequirement{} = requirement) do
    %{
      Fields.evidence_kind() => requirement.evidence_kind,
      Fields.required_fields() => requirement.required_fields,
      Fields.trust_classes() => requirement.trust_classes
    }
    |> put_optional(Fields.required(), requirement.required)
    |> put_optional(Fields.matcher(), ref_to_map(requirement.matcher))
    |> put_optional(Fields.extensions(), ref_to_map(requirement.extensions))
  end

  def to_map(%EvidenceRef{} = ref) do
    %{
      Fields.evidence_id() => ref.evidence_id,
      Fields.evidence_kind() => ref.evidence_kind,
      Fields.source() => ref.source,
      Fields.producer() => ref.producer,
      Fields.observed_at() => ref.observed_at,
      Fields.payload() => ref.payload
    }
    |> put_optional(Fields.evidence_context_key(), ref.context_key)
    |> put_optional(Fields.run_id(), ref.run_id)
    |> put_optional(Fields.task_id(), ref.task_id)
    |> put_optional(Fields.extensions(), ref_to_map(ref.extensions))
  end

  defp put_optional(record, _key, nil), do: record
  defp put_optional(record, _key, []), do: record
  defp put_optional(record, key, value), do: Map.put(record, key, value)

  defp ref_to_map(nil), do: nil
  defp ref_to_map(%_{} = ref), do: to_map(ref)
  defp ref_to_map(ref) when is_map(ref), do: ref
end
