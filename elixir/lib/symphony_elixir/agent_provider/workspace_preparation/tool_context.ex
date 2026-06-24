defmodule SymphonyElixir.AgentProvider.WorkspacePreparation.ToolContext do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.CompositeSource.Context, as: CompositeSourceContext
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.ToolPlan

  @empty_exposure "prepare_empty"

  @spec put(keyword()) :: {:ok, keyword()} | {:error, term()}
  def put(opts) when is_list(opts) do
    with {:ok, tool_context} <- resolve(opts) do
      {:ok, Keyword.put(opts, :tool_context, tool_context)}
    end
  end

  @spec resolve(keyword()) :: {:ok, Context.t()} | {:error, term()}
  def resolve(opts) when is_list(opts) do
    cond do
      explicit_tool_context?(opts) ->
        {:ok, Context.from_opts(opts)}

      true ->
        {:ok, empty_context(opts)}
    end
  end

  defp empty_context(opts) when is_list(opts) do
    %Context{
      source_context: CompositeSourceContext.empty(),
      tool_plan:
        ToolPlan.new!(
          exposure: @empty_exposure,
          required_capabilities: [],
          tool_names: [],
          resolved_tools: [],
          reason: "workspace_prepare_without_workflow_context"
        )
    }
  end

  defp explicit_tool_context?(opts) do
    case Keyword.get(opts, :tool_context) do
      %Context{} ->
        true

      %{"tool_specs" => tool_specs} when is_list(tool_specs) ->
        true

      _context ->
        false
    end
  end
end
