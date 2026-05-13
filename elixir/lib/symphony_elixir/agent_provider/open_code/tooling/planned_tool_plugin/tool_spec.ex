defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin.ToolSpec do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Spec

  @spec normalize(map()) :: map()
  def normalize(tool_spec) when is_map(tool_spec) do
    case Spec.normalize(tool_spec) do
      {:ok, normalized} ->
        normalized

      :error ->
        %{
          "name" => "planned_tool",
          "description" => "Execute Symphony planned tool planned_tool.",
          "inputSchema" => %{"type" => "object", "additionalProperties" => true}
        }
    end
  end

  @spec name(map()) :: String.t()
  def name(tool_spec) when is_map(tool_spec) do
    case Map.get(tool_spec, "name") || Map.get(tool_spec, :name) do
      name when is_binary(name) and name != "" -> name
      _name -> "planned_tool"
    end
  end

  @spec description(map(), String.t()) :: String.t()
  def description(tool_spec, name) when is_map(tool_spec) and is_binary(name) do
    case Map.get(tool_spec, "description") || Map.get(tool_spec, :description) do
      description when is_binary(description) and description != "" -> description
      _description -> "Execute Symphony planned tool #{name}."
    end
  end
end
