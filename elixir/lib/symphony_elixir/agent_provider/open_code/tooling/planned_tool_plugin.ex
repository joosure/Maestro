defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin.{
    SchemaRenderer,
    Template,
    ToolSpec
  }

  @spec render(map()) :: String.t()
  def render(tool_spec) when is_map(tool_spec) do
    tool_spec = ToolSpec.normalize(tool_spec)
    tool_name = ToolSpec.name(tool_spec)

    Template.render(%{
      tool_name: tool_name,
      description: ToolSpec.description(tool_spec, tool_name),
      args_source: SchemaRenderer.args_source(tool_spec)
    })
  end
end
