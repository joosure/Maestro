defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection do
  @moduledoc """
  Projection boundary between workflow adoption records and Agent plan storage.

  `Workflow.StructuredExecutionPlan` owns tracker/profile/route/Workpad
  adoption fields. `Agent.ExecutionPlan.Store` owns generic plan persistence.
  This module is the only place where workflow records are translated into the
  provider-neutral `agent.execution_plan.v1` shape.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection.Context
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection.ExtensionMapping
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: WorkflowContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  @agent_plan_projection_keys [
    AgentFields.plan_id(),
    AgentFields.status(),
    AgentFields.items(),
    AgentFields.rendering(),
    AgentFields.created_at(),
    AgentFields.updated_at(),
    AgentFields.revision(),
    AgentFields.extensions()
  ]

  @spec envelope(map()) :: map()
  def envelope(workflow_plan) when is_map(workflow_plan) do
    workflow_plan
    |> Map.take(WorkflowFields.envelope_identity_keys())
    |> Map.put(WorkflowFields.schema(), WorkflowContract.schema_id())
    |> Map.put(WorkflowFields.status(), Map.get(workflow_plan, WorkflowFields.status()))
  end

  @spec to_agent_plan(map()) :: map()
  def to_agent_plan(workflow_plan) when is_map(workflow_plan) do
    workflow_plan
    |> Map.take(@agent_plan_projection_keys)
    |> Map.put(AgentFields.schema(), AgentContract.schema_id())
    |> Map.put(AgentFields.context(), Context.build(workflow_plan))
    |> Map.update!(AgentFields.status(), &agent_plan_status/1)
    |> Map.update!(AgentFields.items(), fn items -> Enum.map(items, &ExtensionMapping.to_agent_item/1) end)
    |> ExtensionMapping.put_plan_status_extension(Map.get(workflow_plan, WorkflowFields.status()))
  end

  @spec from_agent_plan(map(), map()) :: map()
  def from_agent_plan(agent_plan, envelope) when is_map(agent_plan) and is_map(envelope) do
    agent_plan
    |> Map.take(@agent_plan_projection_keys)
    |> Map.merge(Map.drop(envelope, [WorkflowFields.status()]))
    |> Map.put(WorkflowFields.schema(), WorkflowContract.schema_id())
    |> Map.put(WorkflowFields.status(), Map.get(envelope, WorkflowFields.status()) || ExtensionMapping.workflow_plan_status(agent_plan))
    |> Map.update!(WorkflowFields.items(), fn items -> Enum.map(items, &ExtensionMapping.from_agent_item/1) end)
    |> ExtensionMapping.remove_plan_extension()
  end

  defp agent_plan_status(status), do: WorkflowContract.agent_plan_status_for_workflow_status(status)
end
