defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Values do
  @moduledoc """
  Stable workflow execution-plan schema identifiers and enum extensions.

  Generic status, item, owner, source, and trust-class semantics are delegated
  to `SymphonyElixir.Agent.ExecutionPlan.Contract`. This module owns only the
  workflow adoption extensions over that generic contract.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentExecutionPlanContract

  @schema_id "workflow.execution_plan.v1"

  @handoff_ready_plan_status "handoff_ready"
  @workflow_plan_statuses [@handoff_ready_plan_status]
  @plan_statuses AgentExecutionPlanContract.plan_statuses() ++ @workflow_plan_statuses
  @terminal_plan_statuses AgentExecutionPlanContract.terminal_plan_statuses()
  @agent_plan_status_by_workflow_status %{
    @handoff_ready_plan_status => AgentExecutionPlanContract.active_plan_status()
  }
  @workflow_plan_status_transitions %{
    AgentExecutionPlanContract.active_plan_status() => [@handoff_ready_plan_status],
    @handoff_ready_plan_status => [AgentExecutionPlanContract.active_plan_status(), AgentExecutionPlanContract.closed_plan_status()]
  }
  @plan_status_transitions Map.merge(
                             AgentExecutionPlanContract.plan_status_transitions(),
                             @workflow_plan_status_transitions,
                             fn _status, generic_transitions, workflow_transitions ->
                               Enum.uniq(generic_transitions ++ workflow_transitions)
                             end
                           )

  @item_statuses AgentExecutionPlanContract.item_statuses()
  @terminal_item_statuses AgentExecutionPlanContract.terminal_item_statuses()
  @item_status_transitions AgentExecutionPlanContract.item_status_transitions()
  @handoff_record_item_kind "handoff_record"
  @state_transition_item_kind "state_transition"
  @item_kinds AgentExecutionPlanContract.item_kinds() ++ [@handoff_record_item_kind, @state_transition_item_kind]
  @handoff_blocking_criticality "handoff_blocking"
  @profile_required_criticality "profile_required"
  @workflow_evidence_required_criticalities [@handoff_blocking_criticality, @profile_required_criticality]
  @criticalities AgentExecutionPlanContract.criticalities() ++ @workflow_evidence_required_criticalities
  @profile_owner "profile"
  @owners AgentExecutionPlanContract.owners() ++ [@profile_owner]
  @profile_source "profile"
  @agent_source "agent"
  @backend_source "backend"
  @template_source "template"
  @sources AgentExecutionPlanContract.sources() ++ [@profile_source, @agent_source, @backend_source, @template_source]
  @trust_classes AgentExecutionPlanContract.trust_classes()

  @criticality_display_labels [
    {@handoff_blocking_criticality, "Handoff Blocking"},
    {@profile_required_criticality, "Profile Required"},
    {AgentExecutionPlanContract.informational_criticality(), "Informational"}
  ]

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec plan_statuses() :: [String.t()]
  def plan_statuses, do: @plan_statuses

  @spec active_plan_status() :: String.t()
  def active_plan_status, do: AgentExecutionPlanContract.active_plan_status()

  @spec closed_plan_status() :: String.t()
  def closed_plan_status, do: AgentExecutionPlanContract.closed_plan_status()

  @spec superseded_plan_status() :: String.t()
  def superseded_plan_status, do: AgentExecutionPlanContract.superseded_plan_status()

  @spec workflow_plan_statuses() :: [String.t()]
  def workflow_plan_statuses, do: @workflow_plan_statuses

  @spec handoff_ready_plan_status() :: String.t()
  def handoff_ready_plan_status, do: @handoff_ready_plan_status

  @spec terminal_plan_statuses() :: [String.t()]
  def terminal_plan_statuses, do: @terminal_plan_statuses

  @spec agent_plan_status_by_workflow_status() :: %{String.t() => String.t()}
  def agent_plan_status_by_workflow_status, do: @agent_plan_status_by_workflow_status

  @spec agent_plan_status_for_workflow_status(term()) :: term()
  def agent_plan_status_for_workflow_status(status) when is_binary(status) do
    Map.get(@agent_plan_status_by_workflow_status, status, status)
  end

  def agent_plan_status_for_workflow_status(status), do: status

  @spec plan_status_transitions() :: %{String.t() => [String.t()]}
  def plan_status_transitions, do: @plan_status_transitions

  @spec workflow_plan_status_transitions() :: %{String.t() => [String.t()]}
  def workflow_plan_status_transitions, do: @workflow_plan_status_transitions

  @spec item_statuses() :: [String.t()]
  def item_statuses, do: @item_statuses

  @spec terminal_item_statuses() :: [String.t()]
  def terminal_item_statuses, do: @terminal_item_statuses

  @spec item_status_transitions() :: %{String.t() => [String.t()]}
  def item_status_transitions, do: @item_status_transitions

  @spec item_kinds() :: [String.t()]
  def item_kinds, do: @item_kinds

  @spec handoff_record_item_kind() :: String.t()
  def handoff_record_item_kind, do: @handoff_record_item_kind

  @spec state_transition_item_kind() :: String.t()
  def state_transition_item_kind, do: @state_transition_item_kind

  @spec criticalities() :: [String.t()]
  def criticalities, do: @criticalities

  @spec evidence_required_criticalities() :: [String.t()]
  def evidence_required_criticalities, do: AgentExecutionPlanContract.evidence_required_criticalities() ++ @workflow_evidence_required_criticalities

  @spec handoff_blocking_criticality() :: String.t()
  def handoff_blocking_criticality, do: @handoff_blocking_criticality

  @spec profile_required_criticality() :: String.t()
  def profile_required_criticality, do: @profile_required_criticality

  @spec informational_criticality() :: String.t()
  def informational_criticality, do: AgentExecutionPlanContract.informational_criticality()

  @spec criticality_display_labels() :: [{String.t(), String.t()}]
  def criticality_display_labels, do: @criticality_display_labels

  @spec owners() :: [String.t()]
  def owners, do: @owners

  @spec profile_owner() :: String.t()
  def profile_owner, do: @profile_owner

  @spec agent_owner() :: String.t()
  def agent_owner, do: AgentExecutionPlanContract.agent_owner()

  @spec sources() :: [String.t()]
  def sources, do: @sources

  @spec profile_source() :: String.t()
  def profile_source, do: @profile_source

  @spec agent_source() :: String.t()
  def agent_source, do: @agent_source

  @spec backend_source() :: String.t()
  def backend_source, do: @backend_source

  @spec template_source() :: String.t()
  def template_source, do: @template_source

  @spec trust_classes() :: [String.t()]
  def trust_classes, do: @trust_classes

  @spec plan_status?(term()) :: boolean()
  def plan_status?(value), do: value in @plan_statuses

  @spec terminal_plan_status?(term()) :: boolean()
  def terminal_plan_status?(value), do: value in @terminal_plan_statuses

  @spec item_status?(term()) :: boolean()
  def item_status?(value), do: value in @item_statuses

  @spec terminal_item_status?(term()) :: boolean()
  def terminal_item_status?(value), do: value in @terminal_item_statuses

  @spec item_kind?(term()) :: boolean()
  def item_kind?(value), do: value in @item_kinds

  @spec criticality?(term()) :: boolean()
  def criticality?(value), do: value in @criticalities

  @spec evidence_required_criticality?(term()) :: boolean()
  def evidence_required_criticality?(value), do: value in evidence_required_criticalities()

  @spec owner?(term()) :: boolean()
  def owner?(value), do: value in @owners

  @spec source?(term()) :: boolean()
  def source?(value), do: value in @sources

  @spec trust_class?(term()) :: boolean()
  def trust_class?(value), do: value in @trust_classes
end
