defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.ErrorCodes do
  @moduledoc """
  Machine-code contract for structured-plan Workpad writing.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.ErrorCodes, as: RenderingErrorCodes

  @render_workpad_gate_disabled "render_workpad_gate_disabled"

  @spec rendering_failed() :: String.t()
  defdelegate rendering_failed, to: RenderingErrorCodes

  @spec render_workpad_gate_disabled() :: String.t()
  def render_workpad_gate_disabled, do: @render_workpad_gate_disabled
end
