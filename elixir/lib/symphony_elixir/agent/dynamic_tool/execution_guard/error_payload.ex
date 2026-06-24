defmodule SymphonyElixir.Agent.DynamicTool.ExecutionGuard.ErrorPayload do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.Decision
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @spec from_decision(Decision.t()) :: map()
  def from_decision(%Decision{code: code, message: message, details: details}) do
    Response.error_payload(code, message, details)
  end
end
