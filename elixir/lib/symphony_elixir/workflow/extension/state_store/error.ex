defmodule SymphonyElixir.Workflow.Extension.StateStore.Error do
  @moduledoc """
  Bounded error envelope for workflow extension state-store mechanics.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @spec build(term(), term()) :: map()
  def build(reason, value) do
    %{
      code: ErrorCodes.state_store_error(),
      message: "Workflow extension state store operation failed.",
      reason: reason,
      value_type: Diagnostics.detailed_type_atom(value)
    }
  end
end
