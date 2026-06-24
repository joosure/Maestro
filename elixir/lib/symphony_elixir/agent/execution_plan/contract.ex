defmodule SymphonyElixir.Agent.ExecutionPlan.Contract do
  @moduledoc """
  Stable identifiers and enum values for provider-neutral Agent execution plans.

  Domain adoption layers can define additional namespaced fields or profile
  mappings, but the generic contract stays free of workflow, tracker, Workpad,
  and readiness-specific fields.
  """

  @schema_id "agent.execution_plan.v1"

  @agent_run_context_kind "agent_run"
  @tool_task_context_kind "tool_task"
  @execution_recipe_run_context_kind "execution_recipe_run"
  @workflow_run_context_kind "workflow_run"
  @context_kinds [
    @agent_run_context_kind,
    @tool_task_context_kind,
    @execution_recipe_run_context_kind,
    @workflow_run_context_kind
  ]

  @chat_context_source "chat"
  @api_context_source "api"
  @agent_context_source "agent"
  @workflow_context_source "workflow"
  @recipe_context_source "recipe"
  @system_context_source "system"
  @context_sources [
    @chat_context_source,
    @api_context_source,
    @agent_context_source,
    @workflow_context_source,
    @recipe_context_source,
    @system_context_source
  ]

  @planning_context_mode "planning"
  @execution_context_mode "execution"
  @reconciliation_context_mode "reconciliation"
  @context_modes [
    @planning_context_mode,
    @execution_context_mode,
    @reconciliation_context_mode
  ]

  @draft_plan_status "draft"
  @active_plan_status "active"
  @blocked_plan_status "blocked"
  @closed_plan_status "closed"
  @superseded_plan_status "superseded"
  @plan_statuses [
    @draft_plan_status,
    @active_plan_status,
    @blocked_plan_status,
    @closed_plan_status,
    @superseded_plan_status
  ]
  @terminal_plan_statuses [@closed_plan_status, @superseded_plan_status]
  @plan_status_transitions %{
    @draft_plan_status => [@active_plan_status, @superseded_plan_status],
    @active_plan_status => [@blocked_plan_status, @closed_plan_status, @superseded_plan_status],
    @blocked_plan_status => [@active_plan_status, @closed_plan_status],
    @closed_plan_status => [],
    @superseded_plan_status => []
  }

  @pending_item_status "pending"
  @in_progress_item_status "in_progress"
  @blocked_item_status "blocked"
  @complete_item_status "complete"
  @skipped_item_status "skipped"
  @failed_item_status "failed"
  @superseded_item_status "superseded"
  @item_statuses [
    @pending_item_status,
    @in_progress_item_status,
    @blocked_item_status,
    @complete_item_status,
    @skipped_item_status,
    @failed_item_status,
    @superseded_item_status
  ]
  @terminal_item_statuses [@superseded_item_status]
  @item_status_transitions %{
    @pending_item_status => [@in_progress_item_status, @complete_item_status, @blocked_item_status, @skipped_item_status],
    @in_progress_item_status => [@complete_item_status, @blocked_item_status, @failed_item_status],
    @blocked_item_status => [@pending_item_status, @in_progress_item_status],
    @failed_item_status => [@pending_item_status, @superseded_item_status],
    @complete_item_status => [@in_progress_item_status, @superseded_item_status],
    @skipped_item_status => [@pending_item_status],
    @superseded_item_status => []
  }

  @agent_step_item_kind "agent_step"
  @tool_task_item_kind "tool_task"
  @tool_evidence_item_kind "tool_evidence"
  @validation_item_kind "validation"
  @manual_external_item_kind "manual_external"
  @item_kinds [
    @agent_step_item_kind,
    @tool_task_item_kind,
    @tool_evidence_item_kind,
    @validation_item_kind,
    @manual_external_item_kind
  ]
  @critical_criticality "critical"
  @policy_required_criticality "policy_required"
  @task_required_criticality "task_required"
  @informational_criticality "informational"
  @criticalities [
    @critical_criticality,
    @policy_required_criticality,
    @task_required_criticality,
    @informational_criticality
  ]
  @evidence_required_criticalities [@critical_criticality, @policy_required_criticality]
  @backend_owner "backend"
  @policy_owner "policy"
  @agent_owner "agent"
  @operator_owner "operator"
  @owners [@backend_owner, @policy_owner, @agent_owner, @operator_owner]
  @execution_contract_source "execution_contract"
  @policy_skeleton_source "policy_skeleton"
  @agent_draft_source "agent_draft"
  @runtime_reconciliation_source "runtime_reconciliation"
  @migration_source "migration"
  @manual_override_source "manual_override"
  @sources [
    @execution_contract_source,
    @policy_skeleton_source,
    @agent_draft_source,
    @runtime_reconciliation_source,
    @migration_source,
    @manual_override_source
  ]
  @backend_observed_trust_class "backend_observed"
  @tool_generated_trust_class "tool_generated"
  @agent_requested_trust_class "agent_requested"
  @agent_declared_trust_class "agent_declared"
  @provider_observed_trust_class "provider_observed"
  @repo_observed_trust_class "repo_observed"
  @tracker_observed_trust_class "tracker_observed"
  @trust_classes [
    @backend_observed_trust_class,
    @tool_generated_trust_class,
    @agent_requested_trust_class,
    @agent_declared_trust_class,
    @provider_observed_trust_class,
    @repo_observed_trust_class,
    @tracker_observed_trust_class
  ]

  @snapshot_capability "agent.execution_plan.snapshot"
  @upsert_capability "agent.execution_plan.upsert"
  @update_item_capability "agent.execution_plan.update_item"
  @append_evidence_capability "agent.execution_plan.append_evidence"

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec context_kinds() :: [String.t()]
  def context_kinds, do: @context_kinds

  @spec agent_run_context_kind() :: String.t()
  def agent_run_context_kind, do: @agent_run_context_kind

  @spec workflow_run_context_kind() :: String.t()
  def workflow_run_context_kind, do: @workflow_run_context_kind

  @spec context_sources() :: [String.t()]
  def context_sources, do: @context_sources

  @spec agent_context_source() :: String.t()
  def agent_context_source, do: @agent_context_source

  @spec workflow_context_source() :: String.t()
  def workflow_context_source, do: @workflow_context_source

  @spec context_modes() :: [String.t()]
  def context_modes, do: @context_modes

  @spec execution_context_mode() :: String.t()
  def execution_context_mode, do: @execution_context_mode

  @spec plan_statuses() :: [String.t()]
  def plan_statuses, do: @plan_statuses

  @spec draft_plan_status() :: String.t()
  def draft_plan_status, do: @draft_plan_status

  @spec active_plan_status() :: String.t()
  def active_plan_status, do: @active_plan_status

  @spec closed_plan_status() :: String.t()
  def closed_plan_status, do: @closed_plan_status

  @spec superseded_plan_status() :: String.t()
  def superseded_plan_status, do: @superseded_plan_status

  @spec terminal_plan_statuses() :: [String.t()]
  def terminal_plan_statuses, do: @terminal_plan_statuses

  @spec plan_status_transitions() :: %{String.t() => [String.t()]}
  def plan_status_transitions, do: @plan_status_transitions

  @spec item_statuses() :: [String.t()]
  def item_statuses, do: @item_statuses

  @spec pending_item_status() :: String.t()
  def pending_item_status, do: @pending_item_status

  @spec in_progress_item_status() :: String.t()
  def in_progress_item_status, do: @in_progress_item_status

  @spec blocked_item_status() :: String.t()
  def blocked_item_status, do: @blocked_item_status

  @spec terminal_item_statuses() :: [String.t()]
  def terminal_item_statuses, do: @terminal_item_statuses

  @spec complete_item_status() :: String.t()
  def complete_item_status, do: @complete_item_status

  @spec skipped_item_status() :: String.t()
  def skipped_item_status, do: @skipped_item_status

  @spec failed_item_status() :: String.t()
  def failed_item_status, do: @failed_item_status

  @spec superseded_item_status() :: String.t()
  def superseded_item_status, do: @superseded_item_status

  @spec item_status_transitions() :: %{String.t() => [String.t()]}
  def item_status_transitions, do: @item_status_transitions

  @spec item_kinds() :: [String.t()]
  def item_kinds, do: @item_kinds

  @spec agent_step_item_kind() :: String.t()
  def agent_step_item_kind, do: @agent_step_item_kind

  @spec tool_task_item_kind() :: String.t()
  def tool_task_item_kind, do: @tool_task_item_kind

  @spec tool_evidence_item_kind() :: String.t()
  def tool_evidence_item_kind, do: @tool_evidence_item_kind

  @spec validation_item_kind() :: String.t()
  def validation_item_kind, do: @validation_item_kind

  @spec criticalities() :: [String.t()]
  def criticalities, do: @criticalities

  @spec policy_required_criticality() :: String.t()
  def policy_required_criticality, do: @policy_required_criticality

  @spec evidence_required_criticalities() :: [String.t()]
  def evidence_required_criticalities, do: @evidence_required_criticalities

  @spec informational_criticality() :: String.t()
  def informational_criticality, do: @informational_criticality

  @spec owners() :: [String.t()]
  def owners, do: @owners

  @spec backend_owner() :: String.t()
  def backend_owner, do: @backend_owner

  @spec policy_owner() :: String.t()
  def policy_owner, do: @policy_owner

  @spec agent_owner() :: String.t()
  def agent_owner, do: @agent_owner

  @spec sources() :: [String.t()]
  def sources, do: @sources

  @spec policy_skeleton_source() :: String.t()
  def policy_skeleton_source, do: @policy_skeleton_source

  @spec agent_draft_source() :: String.t()
  def agent_draft_source, do: @agent_draft_source

  @spec runtime_reconciliation_source() :: String.t()
  def runtime_reconciliation_source, do: @runtime_reconciliation_source

  @spec trust_classes() :: [String.t()]
  def trust_classes, do: @trust_classes

  @spec tool_generated_trust_class() :: String.t()
  def tool_generated_trust_class, do: @tool_generated_trust_class

  @spec agent_declared_trust_class() :: String.t()
  def agent_declared_trust_class, do: @agent_declared_trust_class

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
  def evidence_required_criticality?(value), do: value in @evidence_required_criticalities

  @spec owner?(term()) :: boolean()
  def owner?(value), do: value in @owners

  @spec source?(term()) :: boolean()
  def source?(value), do: value in @sources

  @spec trust_class?(term()) :: boolean()
  def trust_class?(value), do: value in @trust_classes

  @spec context_kind?(term()) :: boolean()
  def context_kind?(value), do: value in @context_kinds

  @spec context_source?(term()) :: boolean()
  def context_source?(value), do: value in @context_sources

  @spec context_mode?(term()) :: boolean()
  def context_mode?(value), do: value in @context_modes

  @spec snapshot_capability() :: String.t()
  def snapshot_capability, do: @snapshot_capability

  @spec upsert_capability() :: String.t()
  def upsert_capability, do: @upsert_capability

  @spec update_item_capability() :: String.t()
  def update_item_capability, do: @update_item_capability

  @spec append_evidence_capability() :: String.t()
  def append_evidence_capability, do: @append_evidence_capability
end
