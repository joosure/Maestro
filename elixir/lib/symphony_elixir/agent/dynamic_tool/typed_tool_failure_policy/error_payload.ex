defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.ErrorPayload do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{BlockedDecision, FailureScope}
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @details_key "details"
  @failure_count_key "failure_count"
  @failure_threshold_key "failure_threshold"
  @missing_evidence_key "missing_evidence"
  @original_code_key "original_code"
  @original_details_key "original_details"
  @remediation_actions_key "remediation_actions"
  @resource_key "resource"
  @retryable_key "retryable"
  @run_id_key "run_id"
  @tool_key "tool"

  @spec from_blocked_decision(BlockedDecision.t()) :: map()
  def from_blocked_decision(%BlockedDecision{} = decision) do
    Response.error_payload(decision.blocked_code, decision.message, %{
      @retryable_key => false,
      @details_key => %{
        @original_code_key => decision.original_error_code,
        @retryable_key => false,
        @failure_count_key => decision.failure_count,
        @failure_threshold_key => decision.failure_threshold,
        @run_id_key => decision.scope.run_id,
        @resource_key => FailureScope.resource_map(decision.scope),
        @tool_key => decision.scope.tool,
        @missing_evidence_key => decision.missing_evidence,
        @remediation_actions_key => decision.remediation_actions,
        @original_details_key => decision.original_details
      }
    })
    |> Serializer.json_safe_value()
  end
end
