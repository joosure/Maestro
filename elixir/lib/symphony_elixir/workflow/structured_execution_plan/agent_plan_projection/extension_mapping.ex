defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection.ExtensionMapping do
  @moduledoc """
  Maps workflow adoption values into Agent plan extensions and back.

  Generic Agent execution plans keep their own stable item/evidence semantics.
  Workflow-only item kind, criticality, owner, source, status, and evidence scope
  are carried through namespaced extensions at this boundary.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: WorkflowContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  @plan_extension_key WorkflowContract.plan_extension_key()
  @item_extension_key WorkflowContract.item_extension_key()
  @evidence_extension_key WorkflowContract.evidence_extension_key()

  @workflow_item_kind_by_agent_item_kind %{
    WorkflowContract.handoff_record_item_kind() => AgentContract.validation_item_kind(),
    WorkflowContract.state_transition_item_kind() => AgentContract.tool_task_item_kind()
  }

  @workflow_criticality_by_agent_criticality %{
    WorkflowContract.handoff_blocking_criticality() => AgentContract.policy_required_criticality(),
    WorkflowContract.profile_required_criticality() => AgentContract.policy_required_criticality()
  }

  @workflow_owner_by_agent_owner %{
    WorkflowContract.profile_owner() => AgentContract.policy_owner()
  }

  @workflow_source_by_agent_source %{
    WorkflowContract.agent_source() => AgentContract.agent_draft_source(),
    WorkflowContract.backend_source() => AgentContract.runtime_reconciliation_source(),
    WorkflowContract.profile_source() => AgentContract.policy_skeleton_source(),
    WorkflowContract.template_source() => AgentContract.policy_skeleton_source()
  }

  @spec put_plan_status_extension(map(), term()) :: map()
  def put_plan_status_extension(record, workflow_status) when is_map(record) do
    put_plan_extension(record, AgentFields.status(), workflow_status)
  end

  @spec workflow_plan_status(map()) :: term()
  def workflow_plan_status(agent_plan) when is_map(agent_plan) do
    agent_plan
    |> plan_extension()
    |> Map.get(AgentFields.status(), Map.get(agent_plan, AgentFields.status()))
  end

  @spec remove_plan_extension(map()) :: map()
  def remove_plan_extension(record), do: remove_namespaced_extension(record, @plan_extension_key)

  @spec to_agent_item(map()) :: map()
  def to_agent_item(item) when is_map(item) do
    item
    |> Map.update!(AgentFields.kind(), &agent_item_kind/1)
    |> Map.update!(AgentFields.criticality(), &agent_criticality/1)
    |> Map.update!(AgentFields.owned_by(), &agent_owner/1)
    |> Map.update!(AgentFields.source(), &agent_source/1)
    |> Map.update!(AgentFields.evidence_refs(), fn refs -> Enum.map(refs, &to_agent_evidence_ref/1) end)
    |> put_item_workflow_extension(%{
      AgentFields.kind() => Map.get(item, AgentFields.kind()),
      AgentFields.criticality() => Map.get(item, AgentFields.criticality()),
      AgentFields.owned_by() => Map.get(item, AgentFields.owned_by()),
      AgentFields.source() => Map.get(item, AgentFields.source())
    })
  end

  @spec from_agent_item(map()) :: map()
  def from_agent_item(item) when is_map(item) do
    workflow_values = item_workflow_extension(item)

    item
    |> Map.put_new(AgentFields.parent_item_id(), nil)
    |> Map.put(AgentFields.kind(), Map.get(workflow_values, AgentFields.kind(), Map.get(item, AgentFields.kind())))
    |> Map.put(
      AgentFields.criticality(),
      Map.get(workflow_values, AgentFields.criticality(), Map.get(item, AgentFields.criticality()))
    )
    |> Map.put(
      AgentFields.owned_by(),
      Map.get(workflow_values, AgentFields.owned_by(), Map.get(item, AgentFields.owned_by()))
    )
    |> Map.put(AgentFields.source(), Map.get(workflow_values, AgentFields.source(), Map.get(item, AgentFields.source())))
    |> Map.update!(AgentFields.evidence_refs(), fn refs -> Enum.map(refs, &from_agent_evidence_ref/1) end)
    |> remove_namespaced_extension(@item_extension_key)
  end

  defp agent_item_kind(value) when is_binary(value) do
    cond do
      AgentContract.item_kind?(value) -> value
      true -> Map.fetch!(@workflow_item_kind_by_agent_item_kind, value)
    end
  end

  defp agent_item_kind(value), do: value

  defp agent_criticality(value) when is_binary(value) do
    cond do
      AgentContract.criticality?(value) -> value
      true -> Map.fetch!(@workflow_criticality_by_agent_criticality, value)
    end
  end

  defp agent_criticality(value), do: value

  defp agent_owner(value) when is_binary(value) do
    cond do
      AgentContract.owner?(value) -> value
      true -> Map.fetch!(@workflow_owner_by_agent_owner, value)
    end
  end

  defp agent_owner(value), do: value

  defp agent_source(value) when is_binary(value) do
    cond do
      AgentContract.source?(value) -> value
      true -> Map.fetch!(@workflow_source_by_agent_source, value)
    end
  end

  defp agent_source(value), do: value

  defp to_agent_evidence_ref(ref) do
    ref
    |> Map.delete(WorkflowFields.issue_id())
    |> put_evidence_workflow_extension(%{WorkflowFields.issue_id() => Map.get(ref, WorkflowFields.issue_id())})
  end

  defp from_agent_evidence_ref(ref) do
    workflow_values = evidence_workflow_extension(ref)

    case Map.get(workflow_values, WorkflowFields.issue_id()) do
      issue_id when is_binary(issue_id) -> Map.put(ref, WorkflowFields.issue_id(), issue_id)
      _issue_id -> ref
    end
    |> remove_namespaced_extension(@evidence_extension_key)
  end

  defp put_plan_extension(record, key, value) do
    Map.update(record, AgentFields.extensions(), %{@plan_extension_key => %{key => value}}, fn extensions ->
      Map.put(extensions, @plan_extension_key, Map.put(plan_extension(record), key, value))
    end)
  end

  defp plan_extension(record) do
    record
    |> Map.get(AgentFields.extensions(), %{})
    |> namespaced_extension(@plan_extension_key)
  end

  defp put_item_workflow_extension(item, workflow_values) do
    put_namespaced_extension(item, @item_extension_key, workflow_values)
  end

  defp item_workflow_extension(item) do
    item
    |> Map.get(AgentFields.extensions(), %{})
    |> namespaced_extension(@item_extension_key)
  end

  defp put_evidence_workflow_extension(ref, workflow_values) do
    put_namespaced_extension(ref, @evidence_extension_key, workflow_values)
  end

  defp evidence_workflow_extension(ref) do
    ref
    |> Map.get(AgentFields.extensions(), %{})
    |> namespaced_extension(@evidence_extension_key)
  end

  defp put_namespaced_extension(record, key, values) do
    Map.update(record, AgentFields.extensions(), %{key => values}, fn extensions ->
      Map.put(extensions, key, values)
    end)
  end

  defp remove_namespaced_extension(record, key) do
    case Map.get(record, AgentFields.extensions()) do
      extensions when is_map(extensions) ->
        cleaned_extensions = Map.delete(extensions, key)

        if map_size(cleaned_extensions) == 0 do
          Map.delete(record, AgentFields.extensions())
        else
          Map.put(record, AgentFields.extensions(), cleaned_extensions)
        end

      _extensions ->
        record
    end
  end

  defp namespaced_extension(extensions, key) when is_map(extensions) do
    case Map.get(extensions, key) do
      values when is_map(values) -> values
      _values -> %{}
    end
  end

  defp namespaced_extension(_extensions, _key), do: %{}
end
