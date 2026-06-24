defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AgentPlanProjection.Context do
  @moduledoc """
  Builds generic Agent execution-plan context from workflow adoption records.

  Workflow-specific tracker/profile/route facts are represented as Agent context
  references at this projection boundary. Generic Agent plan storage never owns
  the workflow envelope fields directly.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: WorkflowContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields, as: WorkflowFields

  @spec build(map()) :: map()
  def build(workflow_plan) when is_map(workflow_plan) do
    workflow_profile = Map.fetch!(workflow_plan, WorkflowFields.workflow_profile())

    %{
      AgentFields.context_kind() => WorkflowContract.workflow_context_kind(),
      AgentFields.workspace_id() => workspace_id(workflow_plan),
      AgentFields.run_id() => Map.fetch!(workflow_plan, WorkflowFields.run_id()),
      AgentFields.source() => WorkflowContract.workflow_context_source(),
      AgentFields.mode() => WorkflowContract.execution_context_mode(),
      AgentFields.workflow_ref() => workflow_ref(workflow_plan, workflow_profile),
      AgentFields.tracker_ref() => tracker_ref(workflow_plan)
    }
  end

  defp workflow_ref(workflow_plan, workflow_profile) do
    %{
      AgentFields.profile_kind() => Map.fetch!(workflow_profile, WorkflowFields.profile_kind()),
      AgentFields.profile_version() => Map.fetch!(workflow_profile, WorkflowFields.profile_version()),
      AgentFields.route_key() => Map.fetch!(workflow_plan, WorkflowFields.route_key()),
      AgentFields.issue_id() => Map.fetch!(workflow_plan, WorkflowFields.issue_id()),
      AgentFields.tracker_kind() => Map.fetch!(workflow_plan, WorkflowFields.tracker_kind())
    }
    |> put_optional(AgentFields.lifecycle_phase(), Map.get(workflow_plan, WorkflowFields.lifecycle_phase()))
    |> put_optional(AgentFields.issue_identifier(), Map.get(workflow_plan, WorkflowFields.issue_identifier()))
  end

  defp tracker_ref(workflow_plan) do
    %{
      AgentFields.tracker_kind() => Map.fetch!(workflow_plan, WorkflowFields.tracker_kind()),
      AgentFields.issue_id() => Map.fetch!(workflow_plan, WorkflowFields.issue_id())
    }
    |> put_optional(AgentFields.issue_identifier(), Map.get(workflow_plan, WorkflowFields.issue_identifier()))
  end

  @spec workspace_id(map()) :: String.t()
  def workspace_id(workflow_plan) when is_map(workflow_plan) do
    [
      Map.get(workflow_plan, WorkflowFields.tracker_kind()),
      Map.get(workflow_plan, WorkflowFields.issue_id())
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(WorkflowContract.workflow_workspace_id_separator())
  end

  defp put_optional(record, _key, nil), do: record
  defp put_optional(record, key, value), do: Map.put(record, key, value)
end
