defmodule SymphonyElixir.Config.TypedToolCapabilities do
  @moduledoc """
  Validates workflow-required typed tool capabilities against captured tools.
  """

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities

  @spec validate_required(map()) :: :ok | {:error, term()}
  def validate_required(settings) when is_map(settings) do
    with {:ok, required_capabilities, _profile_context} <-
           WorkflowCapabilities.required_capabilities(settings),
         tool_context <- DynamicTool.capture_context(),
         fallback_policy <- Application.get_env(:symphony_elixir, :typed_workflow_tool_fallback_policy, %{}),
         {:ok, _resolved_tools} <-
           Inventory.resolve_required(tool_context, required_capabilities, fallback_policy: fallback_policy) do
      :ok
    else
      {:error, {:missing_typed_workflow_tool, capability}} ->
        {:error, typed_tool_error(settings, capability, :missing)}

      {:error, {:ambiguous_typed_workflow_tool, capability, tools}} ->
        {:error, typed_tool_error(settings, capability, {:ambiguous, tools})}

      {:error, {:missing_fallback_workflow_tool, capability, tool}} ->
        {:error, typed_tool_error(settings, capability, {:missing_fallback_tool, tool})}

      {:error, {:deprecated_fallback_workflow_tool, capability, tool}} ->
        {:error, typed_tool_error(settings, capability, {:deprecated_fallback_tool, tool})}

      {:error, {:typed_fallback_workflow_tool, capability, tool, tool_capability}} ->
        {:error, typed_tool_error(settings, capability, {:typed_fallback_tool, tool, tool_capability})}

      {:error, _reason} = error ->
        error
    end
  end

  defp typed_tool_error(settings, capability, reason) do
    case WorkflowCapabilities.required_capabilities(settings) do
      {:ok, _required_capabilities, profile_context} ->
        {:typed_workflow_tool_resolution_failed, profile_context.kind, profile_context.version, capability, reason}

      {:error, profile_reason} ->
        {:typed_workflow_tool_resolution_failed, nil, nil, capability, {:profile_unavailable, profile_reason, reason}}
    end
  end
end
