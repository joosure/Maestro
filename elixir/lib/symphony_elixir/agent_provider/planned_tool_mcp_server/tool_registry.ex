defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.ToolRegistry do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Spec

  @spec json([map()]) :: String.t()
  def json(tool_specs) when is_list(tool_specs) do
    tool_specs
    |> Spec.normalize_many()
    |> Jason.encode!()
  end
end
