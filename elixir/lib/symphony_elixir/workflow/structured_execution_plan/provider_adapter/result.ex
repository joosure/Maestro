defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Result do
  @moduledoc """
  Result payload contract for provider adapter facade functions.
  """

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values, as: ReadinessValues
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Options

  @success_key "success"
  @status_key "status"
  @reason_key "reason"
  @gate_key "gate"
  @plan_changed_key "plan_changed"
  @plan_revision_key "plan_revision"
  @provider_session_event_key "provider_session_event"
  @missing_items_key "missing_items"
  @error_key "error"
  @code_key "code"
  @message_key "message"
  @details_key "details"

  @recorded_status "recorded"
  @skipped_status "skipped"

  @spec skipped() :: map()
  def skipped do
    %{
      @success_key => true,
      @status_key => @skipped_status,
      @reason_key => ErrorCodes.provider_adapters_gate_disabled(),
      @gate_key => Options.gate_key(),
      @plan_changed_key => false
    }
  end

  @spec recorded(String.t(), map(), map()) :: map()
  def recorded(plan_id, updated_plan, normalized_event) do
    %{
      @success_key => true,
      @status_key => @recorded_status,
      AgentFields.plan_id() => plan_id,
      @plan_revision_key => Map.get(updated_plan, AgentFields.revision()),
      @provider_session_event_key => normalized_event
    }
  end

  @spec guard_passed() :: map()
  def guard_passed do
    %{@success_key => true, @status_key => ReadinessValues.passed_status(), @missing_items_key => []}
  end

  @spec guard_blocked([map()]) :: map()
  def guard_blocked(missing_items) when is_list(missing_items) do
    %{
      code: ErrorCodes.structured_plan_missing_required_evidence(),
      message: "Provider-native task completion cannot satisfy structured plan evidence requirements.",
      status: ReadinessValues.blocked_status(),
      missing_items: missing_items
    }
  end

  @spec gate_disabled_typed_failure() :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def gate_disabled_typed_failure do
    typed_failure(
      ErrorCodes.provider_adapters_gate_disabled(),
      "Structured plan provider adapters are disabled.",
      %{@gate_key => Options.gate_key()}
    )
  end

  @spec typed_failure(String.t(), String.t(), map()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def typed_failure(code, message, details) do
    {:failure, %{@error_key => %{@code_key => code, @message_key => message, @details_key => Serializer.json_safe_value(details)}}}
  end
end
