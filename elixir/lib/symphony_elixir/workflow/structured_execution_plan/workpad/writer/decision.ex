defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Decision do
  @moduledoc """
  Workpad identity decisions for structured-plan Workpad writing.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: RenderingContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Result

  @spec for_plan(map()) :: {:ok, map()}
  def for_plan(plan) when is_map(plan) do
    case get_in(plan, [Fields.rendering(), RenderingContract.workpad_id_key()]) do
      workpad_id when is_binary(workpad_id) and workpad_id != "" ->
        {:ok,
         %{
           Result.action_key() => Result.write_action(),
           Result.state_key() => Result.known_state(),
           RenderingContract.workpad_id_key() => workpad_id
         }}

      _workpad_id ->
        {:ok, %{Result.action_key() => Result.write_action(), Result.state_key() => Result.missing_state()}}
    end
  end
end
