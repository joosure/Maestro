defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.PlannedToolMcpServer.{Template, ToolRegistry}

  @spec source([map()]) :: String.t()
  def source(tool_specs) when is_list(tool_specs) do
    Template.render(ToolRegistry.json(tool_specs))
  end
end
