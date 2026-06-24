defmodule SymphonyElixir.Config.TypedToolCapabilities do
  @moduledoc """
  Validates workflow-required typed tool capabilities against captured tools.
  """

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Agent.DynamicTool.Inventory.ResolutionError
  alias SymphonyElixir.Capability.Registry, as: CapabilityRegistry
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities

  @spec validate_required(map()) :: :ok | {:error, term()}
  def validate_required(settings) when is_map(settings) do
    with {:ok, required_capabilities, _profile_context} <-
           WorkflowCapabilities.required_capabilities(settings),
         required_capabilities <- Enum.filter(required_capabilities, &typed_workflow_capability?/1),
         tool_context <- DynamicTool.capture_context(),
         {:ok, _resolved_tools} <-
           Inventory.resolve_required(tool_context, required_capabilities) do
      :ok
    else
      {:error, %ResolutionError{reason: :missing_typed_tool, capability: capability}} ->
        {:error, typed_tool_error(settings, capability, :missing)}

      {:error, %ResolutionError{reason: :ambiguous_typed_tool, capability: capability, tools: tools}} ->
        {:error, typed_tool_error(settings, capability, {:ambiguous, tools})}

      {:error, %ResolutionError{reason: :invalid_required_capability, value: value}} ->
        {:error, typed_tool_error(settings, nil, {:invalid_required_capability, value})}

      {:error, _reason} = error ->
        error
    end
  end

  defp typed_workflow_capability?(capability) when is_binary(capability),
    do: CapabilityRegistry.typed_tool_capability?(capability)

  defp typed_workflow_capability?(_capability), do: false

  defp typed_tool_error(settings, capability, reason) do
    case WorkflowCapabilities.required_capabilities(settings) do
      {:ok, _required_capabilities, profile_context} ->
        {:typed_workflow_tool_resolution_failed, profile_context.kind, profile_context.version, capability, reason}

      {:error, profile_reason} ->
        {:typed_workflow_tool_resolution_failed, nil, nil, capability, {:profile_unavailable, profile_reason, reason}}
    end
  end
end
