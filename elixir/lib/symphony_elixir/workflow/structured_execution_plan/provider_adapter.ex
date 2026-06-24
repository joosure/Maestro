defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter do
  @moduledoc """
  Gated facade for provider-native plan/todo/task adapter behavior.

  The facade records provider-native session events only as non-authoritative
  proposals or display metadata. It is not wired into default agent, MCP, or
  Dynamic Tool paths.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Guard
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderAdapter.Result
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor

  @spec gate_key() :: String.t()
  def gate_key, do: Options.gate_key()

  @spec normalize_event(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def normalize_event(event, opts \\ []) when is_list(opts) do
    case ensure_gate(opts) do
      :ok -> ProviderSessionEvent.normalize(event, opts)
      {:skip, result} -> {:ok, result}
    end
  end

  @spec ingest_event(String.t(), map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, map()}
  def ingest_event(plan_id, event, expected_revision, opts \\ [])
      when is_binary(plan_id) and is_map(event) and is_integer(expected_revision) and is_list(opts) do
    case ensure_gate(opts) do
      :ok ->
        with {:ok, normalized_event} <- ProviderSessionEvent.normalize(event, opts),
             {:ok, updated_plan} <- Store.record_provider_session_event(plan_id, normalized_event, expected_revision, Options.store_opts(opts)) do
          {:ok, Result.recorded(plan_id, updated_plan, normalized_event)}
        end

      {:skip, result} ->
        {:ok, result}
    end
  end

  @spec task_completed_guard(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def task_completed_guard(plan_id, opts \\ []) when is_binary(plan_id) and is_list(opts) do
    case ensure_gate(opts) do
      :ok ->
        with {:ok, plan} <- Store.fetch(plan_id, Options.store_opts(opts)), do: Guard.task_completed(plan)

      {:skip, result} ->
        {:ok, result}
    end
  end

  @spec execute_mcp_tool(String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute_mcp_tool(tool, arguments, opts \\ []) when is_list(opts) do
    case ensure_gate(opts) do
      :ok -> ToolExecutor.execute(tool, arguments, opts)
      {:skip, _result} -> Result.gate_disabled_typed_failure()
    end
  end

  defp ensure_gate(opts) do
    if Options.enabled?(opts) do
      :ok
    else
      {:skip, Result.skipped()}
    end
  end
end
