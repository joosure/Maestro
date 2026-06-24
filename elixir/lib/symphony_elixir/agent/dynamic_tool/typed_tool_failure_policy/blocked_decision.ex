defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.BlockedDecision do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{FailureKey, FailureScope, RetryPolicy}

  @missing_evidence_key "missing_evidence"
  @remediation_actions_key "remediation_actions"

  defstruct scope: nil,
            original_error_code: nil,
            blocked_code: nil,
            message: nil,
            failure_count: nil,
            failure_threshold: nil,
            missing_evidence: [],
            remediation_actions: [],
            original_details: %{}

  @type t :: %__MODULE__{
          scope: FailureScope.t(),
          original_error_code: String.t(),
          blocked_code: String.t(),
          message: String.t(),
          failure_count: pos_integer(),
          failure_threshold: pos_integer(),
          missing_evidence: list(),
          remediation_actions: list(),
          original_details: map()
        }

  @spec new(FailureKey.t(), pos_integer(), pos_integer(), RetryPolicy.t(), map()) :: t()
  def new(%FailureKey{} = key, count, threshold, %RetryPolicy{} = policy, original_details)
      when is_integer(count) and is_integer(threshold) and is_map(original_details) do
    %__MODULE__{
      scope: key.scope,
      original_error_code: key.error_code,
      blocked_code: policy.blocked_code,
      message: policy.message,
      failure_count: count,
      failure_threshold: threshold,
      missing_evidence: detail_list(original_details, @missing_evidence_key),
      remediation_actions: detail_list(original_details, @remediation_actions_key),
      original_details: original_details
    }
  end

  defp detail_list(details, key) when is_map(details) and is_binary(key) do
    details
    |> Map.get(key)
    |> normalize_detail_list()
  end

  defp normalize_detail_list(values) when is_list(values), do: values
  defp normalize_detail_list(nil), do: []
  defp normalize_detail_list(value), do: [value]
end
