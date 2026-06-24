defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract do
  @moduledoc """
  Stable contract for workflow structured-plan Workpad rendering.

  Rendering is a one-way projection. The keys and values in this module are
  output/marker contracts, not inputs for reconstructing canonical plan state
  from Workpad Markdown.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @render_schema "workflow.execution_plan.workpad_render.v1"
  @default_heading "Structured Execution Plan Workpad"
  @fingerprint_placeholder "__pending__"
  @marker_prefix "symphony:structured_execution_plan:v1"
  @max_items 100
  @max_text_chars 160

  @plan_revision_key "plan_revision"
  @rendered_item_count_key "rendered_item_count"
  @fingerprint_key "fingerprint"
  @workpad_id_key "workpad_id"
  @heading_key "heading"
  @body_key "body"
  @marker_key "marker"
  @item_count_key "item_count"
  @items_truncated_key "items_truncated"

  @preview_mode "preview"
  @write_mode "write"
  @render_modes [@preview_mode, @write_mode]
  @completed_item_statuses [AgentContract.complete_item_status(), AgentContract.skipped_item_status()]

  @required_marker_keys [
    Fields.schema(),
    Fields.plan_id(),
    @plan_revision_key,
    Fields.tracker_kind(),
    AgentFields.mode(),
    @rendered_item_count_key,
    @fingerprint_key
  ]
  @allowed_marker_keys @required_marker_keys ++ [@workpad_id_key, Fields.extensions()]
  @marker_line_keys [
    Fields.schema(),
    Fields.plan_id(),
    @plan_revision_key,
    Fields.tracker_kind(),
    AgentFields.mode(),
    @rendered_item_count_key,
    @fingerprint_key
  ]

  @spec render_schema() :: String.t()
  def render_schema, do: @render_schema

  @spec default_heading() :: String.t()
  def default_heading, do: @default_heading

  @spec fingerprint_placeholder() :: String.t()
  def fingerprint_placeholder, do: @fingerprint_placeholder

  @spec marker_prefix() :: String.t()
  def marker_prefix, do: @marker_prefix

  @spec max_items() :: pos_integer()
  def max_items, do: @max_items

  @spec max_text_chars() :: pos_integer()
  def max_text_chars, do: @max_text_chars

  @spec plan_revision_key() :: String.t()
  def plan_revision_key, do: @plan_revision_key

  @spec rendered_item_count_key() :: String.t()
  def rendered_item_count_key, do: @rendered_item_count_key

  @spec fingerprint_key() :: String.t()
  def fingerprint_key, do: @fingerprint_key

  @spec workpad_id_key() :: String.t()
  def workpad_id_key, do: @workpad_id_key

  @spec heading_key() :: String.t()
  def heading_key, do: @heading_key

  @spec body_key() :: String.t()
  def body_key, do: @body_key

  @spec marker_key() :: String.t()
  def marker_key, do: @marker_key

  @spec item_count_key() :: String.t()
  def item_count_key, do: @item_count_key

  @spec items_truncated_key() :: String.t()
  def items_truncated_key, do: @items_truncated_key

  @spec mode_key() :: String.t()
  def mode_key, do: AgentFields.mode()

  @spec preview_mode() :: String.t()
  def preview_mode, do: @preview_mode

  @spec write_mode() :: String.t()
  def write_mode, do: @write_mode

  @spec render_modes() :: [String.t()]
  def render_modes, do: @render_modes

  @spec render_mode?(term()) :: boolean()
  def render_mode?(value), do: value in @render_modes

  @spec completed_item_statuses() :: [String.t()]
  def completed_item_statuses, do: @completed_item_statuses

  @spec completed_item_status?(term()) :: boolean()
  def completed_item_status?(value), do: value in @completed_item_statuses

  @spec required_marker_keys() :: [String.t()]
  def required_marker_keys, do: @required_marker_keys

  @spec allowed_marker_keys() :: [String.t()]
  def allowed_marker_keys, do: @allowed_marker_keys

  @spec marker_line_keys() :: [String.t()]
  def marker_line_keys, do: @marker_line_keys
end
