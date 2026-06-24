defmodule SymphonyElixir.Agent.DynamicTool.Bridge.Audit do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Bridge.Request
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Agent.DynamicTool.Usage
  alias SymphonyElixir.Observability.Redaction

  @spec request_fields(Request.t()) :: map()
  def request_fields(%Request{} = request) do
    tool_context = request.tool_context
    provider_tool = request.provider_tool
    canonical_tool = request.canonical_tool
    arguments = request.arguments
    opts = request.opts
    runtime_metadata = Context.runtime_metadata(tool_context)

    %{
      component: EventContract.dynamic_tool_bridge_component(),
      tool_name: provider_tool,
      provider_tool_name: provider_tool,
      canonical_tool_name: canonical_tool,
      run_id: audit_value(opts, runtime_metadata, :run_id),
      correlation_id: audit_value(opts, runtime_metadata, :run_id),
      issue_id: audit_value(opts, runtime_metadata, :issue_id),
      issue_identifier: audit_value(opts, runtime_metadata, :issue_identifier),
      dynamic_tool_source_kind: Context.source_kind(tool_context),
      agent_provider_kind: audit_value(opts, runtime_metadata, :agent_provider_kind),
      session_id: audit_value(opts, runtime_metadata, :session_id),
      thread_id: audit_value(opts, runtime_metadata, :thread_id),
      turn_id: audit_value(opts, runtime_metadata, :turn_id),
      worker_host: audit_value(opts, runtime_metadata, :worker_host),
      workspace_path: Keyword.get(opts, :workspace),
      payload_summary: Redaction.summarize(arguments)
    }
    |> Map.merge(Usage.audit_fields(tool_context, canonical_tool, opts))
  end

  @spec result_fields(term(), integer(), keyword()) :: map()
  def result_fields(result, started_at_ms, opts \\ []) do
    %{
      duration_ms: elapsed_ms(started_at_ms),
      dynamic_tool_failure_reason: Usage.failure_reason(result),
      dynamic_tool_provider_capability_unavailable_count: Usage.provider_capability_unavailable_count(result),
      dynamic_tool_provider_capability_unavailable: Usage.provider_capability_unavailable_details(result),
      result_summary: Redaction.summarize(result)
    }
    |> Map.merge(diagnostics_fields(result, opts))
  end

  @spec rejection_fields(term(), integer(), keyword()) :: map()
  def rejection_fields(response, started_at_ms, opts \\ []) do
    response
    |> result_fields(started_at_ms, opts)
    |> Map.put(:dynamic_tool_rejection_reason, Usage.failure_reason(response))
  end

  defp diagnostics_fields(result, opts) do
    opts
    |> Keyword.get_lazy(:dynamic_tool_failure_diagnostics, fn ->
      Application.get_env(:symphony_elixir, :dynamic_tool_failure_diagnostics)
    end)
    |> call_diagnostics(result)
  end

  defp call_diagnostics({module, function, extra_args}, result)
       when is_atom(module) and is_atom(function) and is_list(extra_args) do
    apply(module, function, [result | extra_args])
  rescue
    _error -> %{}
  end

  defp call_diagnostics(fun, result) when is_function(fun, 1) do
    fun.(result)
  rescue
    _error -> %{}
  end

  defp call_diagnostics(_diagnostics, _result), do: %{}

  defp audit_value(opts, runtime_metadata, key) when is_list(opts) and is_map(runtime_metadata) do
    Keyword.get(opts, key) || RuntimeMetadata.value(runtime_metadata, key)
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    max(System.monotonic_time(:millisecond) - started_at_ms, 0)
  end
end
