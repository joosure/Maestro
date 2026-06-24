defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Contract do
  @moduledoc """
  Facade for workflow structured execution-plan contracts.

  Submodules own focused contract groups:

  - `Contract.Values` owns schema ids and enum extensions.
  - `Contract.Gates` owns rollout gate keys and defaults.
  - `Contract.Projection` owns workflow-to-Agent projection identifiers.

  Generic execution-plan semantics remain owned by
  `SymphonyElixir.Agent.ExecutionPlan.Contract`.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Projection
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Values

  @spec schema_id() :: String.t()
  defdelegate schema_id, to: Values

  @spec plan_extension_key() :: String.t()
  defdelegate plan_extension_key, to: Projection

  @spec item_extension_key() :: String.t()
  defdelegate item_extension_key, to: Projection

  @spec evidence_extension_key() :: String.t()
  defdelegate evidence_extension_key, to: Projection

  @spec workflow_context_kind() :: String.t()
  defdelegate workflow_context_kind, to: Projection

  @spec workflow_context_source() :: String.t()
  defdelegate workflow_context_source, to: Projection

  @spec execution_context_mode() :: String.t()
  defdelegate execution_context_mode, to: Projection

  @spec workflow_ref_profile_key() :: String.t()
  defdelegate workflow_ref_profile_key, to: Projection

  @spec workflow_workspace_id_separator() :: String.t()
  defdelegate workflow_workspace_id_separator, to: Projection

  @spec gate_defaults() :: %{String.t() => boolean()}
  defdelegate gate_defaults, to: Gates

  @spec gate_keys() :: [String.t()]
  defdelegate gate_keys, to: Gates

  @spec enabled_gate_key() :: String.t()
  defdelegate enabled_gate_key, to: Gates

  @spec render_workpad_gate_key() :: String.t()
  defdelegate render_workpad_gate_key, to: Gates

  @spec transition_readiness_required_gate_key() :: String.t()
  defdelegate transition_readiness_required_gate_key, to: Gates

  @spec provider_adapters_enabled_gate_key() :: String.t()
  defdelegate provider_adapters_enabled_gate_key, to: Gates

  @spec plan_statuses() :: [String.t()]
  defdelegate plan_statuses, to: Values

  @spec active_plan_status() :: String.t()
  defdelegate active_plan_status, to: Values

  @spec closed_plan_status() :: String.t()
  defdelegate closed_plan_status, to: Values

  @spec superseded_plan_status() :: String.t()
  defdelegate superseded_plan_status, to: Values

  @spec workflow_plan_statuses() :: [String.t()]
  defdelegate workflow_plan_statuses, to: Values

  @spec handoff_ready_plan_status() :: String.t()
  defdelegate handoff_ready_plan_status, to: Values

  @spec terminal_plan_statuses() :: [String.t()]
  defdelegate terminal_plan_statuses, to: Values

  @spec agent_plan_status_by_workflow_status() :: %{String.t() => String.t()}
  defdelegate agent_plan_status_by_workflow_status, to: Values

  @spec agent_plan_status_for_workflow_status(term()) :: term()
  defdelegate agent_plan_status_for_workflow_status(status), to: Values

  @spec plan_status_transitions() :: %{String.t() => [String.t()]}
  defdelegate plan_status_transitions, to: Values

  @spec workflow_plan_status_transitions() :: %{String.t() => [String.t()]}
  defdelegate workflow_plan_status_transitions, to: Values

  @spec item_statuses() :: [String.t()]
  defdelegate item_statuses, to: Values

  @spec terminal_item_statuses() :: [String.t()]
  defdelegate terminal_item_statuses, to: Values

  @spec item_status_transitions() :: %{String.t() => [String.t()]}
  defdelegate item_status_transitions, to: Values

  @spec item_kinds() :: [String.t()]
  defdelegate item_kinds, to: Values

  @spec handoff_record_item_kind() :: String.t()
  defdelegate handoff_record_item_kind, to: Values

  @spec state_transition_item_kind() :: String.t()
  defdelegate state_transition_item_kind, to: Values

  @spec criticalities() :: [String.t()]
  defdelegate criticalities, to: Values

  @spec evidence_required_criticalities() :: [String.t()]
  defdelegate evidence_required_criticalities, to: Values

  @spec handoff_blocking_criticality() :: String.t()
  defdelegate handoff_blocking_criticality, to: Values

  @spec profile_required_criticality() :: String.t()
  defdelegate profile_required_criticality, to: Values

  @spec informational_criticality() :: String.t()
  defdelegate informational_criticality, to: Values

  @spec criticality_display_labels() :: [{String.t(), String.t()}]
  defdelegate criticality_display_labels, to: Values

  @spec owners() :: [String.t()]
  defdelegate owners, to: Values

  @spec profile_owner() :: String.t()
  defdelegate profile_owner, to: Values

  @spec agent_owner() :: String.t()
  defdelegate agent_owner, to: Values

  @spec sources() :: [String.t()]
  defdelegate sources, to: Values

  @spec profile_source() :: String.t()
  defdelegate profile_source, to: Values

  @spec agent_source() :: String.t()
  defdelegate agent_source, to: Values

  @spec backend_source() :: String.t()
  defdelegate backend_source, to: Values

  @spec template_source() :: String.t()
  defdelegate template_source, to: Values

  @spec trust_classes() :: [String.t()]
  defdelegate trust_classes, to: Values

  @spec plan_status?(term()) :: boolean()
  defdelegate plan_status?(value), to: Values

  @spec terminal_plan_status?(term()) :: boolean()
  defdelegate terminal_plan_status?(value), to: Values

  @spec item_status?(term()) :: boolean()
  defdelegate item_status?(value), to: Values

  @spec terminal_item_status?(term()) :: boolean()
  defdelegate terminal_item_status?(value), to: Values

  @spec item_kind?(term()) :: boolean()
  defdelegate item_kind?(value), to: Values

  @spec criticality?(term()) :: boolean()
  defdelegate criticality?(value), to: Values

  @spec evidence_required_criticality?(term()) :: boolean()
  defdelegate evidence_required_criticality?(value), to: Values

  @spec owner?(term()) :: boolean()
  defdelegate owner?(value), to: Values

  @spec source?(term()) :: boolean()
  defdelegate source?(value), to: Values

  @spec trust_class?(term()) :: boolean()
  defdelegate trust_class?(value), to: Values
end
