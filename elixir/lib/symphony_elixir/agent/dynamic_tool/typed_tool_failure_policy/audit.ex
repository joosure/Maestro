defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.Audit do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{FailureKey, RetryPolicy, ScopeResolver, Server}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @spec skipped_unscoped(Context.t(), String.t() | nil, term(), keyword(), String.t()) :: :ok
  def skipped_unscoped(%Context{} = tool_context, tool, arguments, opts, code) do
    runtime_metadata = ScopeResolver.runtime_metadata(tool_context)

    ObservabilityLogger.emit(:debug, EventContract.typed_tool_failure_policy_skipped_unscoped_event(), %{
      component: EventContract.dynamic_tool_failure_policy_component(),
      reason: "missing_resource_identity",
      error_code: code,
      tool_name: ScopeResolver.normalize_tool_name(tool),
      run_id: ScopeResolver.run_scope(opts, runtime_metadata),
      session_id: ScopeResolver.scoped_value(opts, runtime_metadata, :session_id),
      turn_id: ScopeResolver.scoped_value(opts, runtime_metadata, :turn_id),
      payload_summary: inspect(ScopeResolver.argument_keys(arguments))
    })

    :ok
  end

  def skipped_unscoped(_tool_context, _tool, _arguments, _opts, _code), do: :ok

  @spec blocked(Context.t(), FailureKey.t(), pos_integer(), pos_integer(), RetryPolicy.t(), keyword()) :: :ok
  def blocked(%Context{} = tool_context, %FailureKey{} = key, count, threshold, %RetryPolicy{} = policy, opts) do
    runtime_metadata = ScopeResolver.runtime_metadata(tool_context)
    scope = key.scope

    fields =
      %{
        component: EventContract.dynamic_tool_failure_policy_component(),
        run_id: scope.run_id,
        session_id: ScopeResolver.scoped_value(opts, runtime_metadata, :session_id),
        turn_id: ScopeResolver.scoped_value(opts, runtime_metadata, :turn_id),
        tool_name: scope.tool,
        error_code: policy.blocked_code,
        original_error_code: key.error_code,
        retryable: false,
        failure_count: count,
        failure_threshold: threshold,
        resource_kind: scope.resource_kind,
        resource_id: scope.resource_id,
        result_summary: "typed_tool_non_retryable_blocker"
      }
      |> Map.merge(additional_fields(scope.resource_kind, scope.resource_id, opts))

    ObservabilityLogger.emit(:warning, EventContract.typed_tool_failure_policy_blocked_event(), fields)

    :ok
  end

  def blocked(_tool_context, _key, _count, _threshold, _policy, _opts), do: :ok

  defp additional_fields(resource_kind, resource_id, opts) do
    opts
    |> Server.audit_fields_fun()
    |> case do
      fun when is_function(fun, 2) -> fun.(resource_kind, resource_id)
      nil -> %{}
    end
    |> case do
      fields when is_map(fields) -> fields
      _fields -> %{}
    end
  end
end
