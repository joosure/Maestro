defmodule SymphonyElixir.AgentProvider.WorkspacePreparation.ToolContext do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context

  @empty_exposure "prepare_empty"
  @empty_source Module.concat(["SymphonyElixir", "Agent", "DynamicTool", "CompositeSource"])

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
    %{
      source: @empty_source,
      source_context: %{
        sources: [],
        tool_specs: [],
        routes: %{}
      },
      source_kind: "composite",
      tool_specs: [],
      tool_metadata: %{},
      tool_environment: %{},
      tool_plan: %{
        exposure: @empty_exposure,
        required_capabilities: [],
        tool_names: [],
        resolved_tools: [],
        reason: "workspace_prepare_without_workflow_context"
      }
    }
  end

  defp explicit_tool_context?(opts) do
    case Keyword.get(opts, :tool_context) do
      %{tool_specs: tool_specs} when is_list(tool_specs) -> true
      _context -> false
    end
  end
end
