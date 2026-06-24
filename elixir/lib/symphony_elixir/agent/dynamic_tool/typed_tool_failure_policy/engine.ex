defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.Engine do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context

  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{
    Audit,
    BlockedDecision,
    ErrorPayload,
    FailureKey,
    FailureScope,
    RetryPolicy,
    ScopeResolver,
    Server
  }

  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @details_key "details"

  @type result :: {:success, term()} | {:failure, term()} | term()

  @spec apply(result(), Context.t(), String.t() | nil, term(), keyword()) :: result()
  def apply({:failure, payload}, %Context{} = tool_context, tool, arguments, opts) do
    case retry_policy(error_code(payload), opts) do
      {code, policy} ->
        record_failure(payload, tool_context, tool, arguments, opts, code, policy)

      nil ->
        {:failure, payload}
    end
  end

  def apply({:failure, _payload} = result, _tool_context, _tool, _arguments, _opts), do: result

  def apply({:success, _payload} = result, %Context{} = tool_context, tool, arguments, opts) do
    reset_tool_scope(tool_context, tool, arguments, opts)
    result
  end

  def apply(result, _tool_context, _tool, _arguments, _opts), do: result

  defp record_failure(payload, tool_context, tool, arguments, opts, code, %RetryPolicy{} = policy) do
    case failure_key(tool_context, tool, arguments, opts, code) do
      {:ok, %FailureKey{} = key} ->
        {count, threshold} = Server.record_failure(key)

        if count >= threshold do
          blocked = blocked_payload(payload, key, count, threshold, policy)
          Audit.blocked(tool_context, key, count, threshold, policy, opts)
          {:failure, blocked}
        else
          {:failure, payload}
        end

      :unscoped ->
        Audit.skipped_unscoped(tool_context, tool, arguments, opts, code)
        {:failure, payload}
    end
  end

  defp reset_tool_scope(%Context{} = tool_context, tool, arguments, opts) do
    case ScopeResolver.scope(tool_context, tool, arguments, opts) do
      {:ok, %FailureScope{} = scope} -> Server.reset_scope(scope)
      :unscoped -> :ok
    end
  end

  defp blocked_payload(payload, %FailureKey{} = key, count, threshold, %RetryPolicy{} = policy) do
    key
    |> BlockedDecision.new(count, threshold, policy, error_details(payload))
    |> ErrorPayload.from_blocked_decision()
  end

  defp failure_key(tool_context, tool, arguments, opts, code) do
    case ScopeResolver.scope(tool_context, tool, arguments, opts) do
      {:ok, %FailureScope{} = scope} ->
        case FailureKey.new(scope, code) do
          {:ok, key} -> {:ok, key}
          :error -> :unscoped
        end

      :unscoped ->
        :unscoped
    end
  end

  defp retry_policy(code, opts) when is_binary(code) do
    opts
    |> Server.retry_policies()
    |> Map.get(code)
    |> case do
      nil -> nil
      %RetryPolicy{} = policy -> {code, policy}
    end
  end

  defp retry_policy(_code, _opts), do: nil

  defp error_code(payload), do: get_in(payload, [Response.error_key(), Response.code_key()])

  defp error_details(payload) do
    case get_in(payload, [Response.error_key(), @details_key]) do
      details when is_map(details) -> details
      _details -> %{}
    end
  end
end
