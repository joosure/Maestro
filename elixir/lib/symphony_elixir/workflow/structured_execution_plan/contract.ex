defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Contract do
  @moduledoc """
  Stable identifiers, enum values, and disabled-by-default gates for
  backend-owned structured execution plans.
  """

  @schema_id "workflow.execution_plan.v1"

  @plan_statuses ~w(draft active blocked handoff_ready closed superseded)
  @terminal_plan_statuses ~w(closed superseded)
  @item_statuses ~w(pending in_progress blocked complete skipped failed superseded)
  @terminal_item_statuses ~w(superseded)
  @item_kinds ~w(agent_step tool_evidence validation handoff_record state_transition manual_external)
  @criticalities ~w(handoff_blocking profile_required informational)
  @owners ~w(backend profile agent operator)
  @sources ~w(profile agent backend template migration)
  @trust_classes ~w(backend_observed tool_generated agent_requested agent_declared tracker_observed)

  @gate_defaults %{
    "workflow.structured_execution_plan.enabled" => false,
    "workflow.structured_execution_plan.render_workpad" => false,
    "workflow.structured_execution_plan.review_handoff_required" => false,
    "workflow.structured_execution_plan.provider_adapters.enabled" => false
  }

  @spec schema_id() :: String.t()
  def schema_id, do: @schema_id

  @spec gate_defaults() :: %{String.t() => boolean()}
  def gate_defaults, do: @gate_defaults

  @spec plan_statuses() :: [String.t()]
  def plan_statuses, do: @plan_statuses

  @spec terminal_plan_statuses() :: [String.t()]
  def terminal_plan_statuses, do: @terminal_plan_statuses

  @spec item_statuses() :: [String.t()]
  def item_statuses, do: @item_statuses

  @spec terminal_item_statuses() :: [String.t()]
  def terminal_item_statuses, do: @terminal_item_statuses

  @spec item_kinds() :: [String.t()]
  def item_kinds, do: @item_kinds

  @spec criticalities() :: [String.t()]
  def criticalities, do: @criticalities

  @spec owners() :: [String.t()]
  def owners, do: @owners

  @spec sources() :: [String.t()]
  def sources, do: @sources

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

  @spec owner?(term()) :: boolean()
  def owner?(value), do: value in @owners

  @spec source?(term()) :: boolean()
  def source?(value), do: value in @sources

  @spec trust_class?(term()) :: boolean()
  def trust_class?(value), do: value in @trust_classes
end
