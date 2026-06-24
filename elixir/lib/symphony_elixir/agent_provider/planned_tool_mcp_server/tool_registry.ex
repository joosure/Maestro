defmodule SymphonyElixir.AgentProvider.PlannedToolMcpServer.ToolRegistry do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Spec

  @spec json([map()]) :: String.t()
  def json(tool_specs) when is_list(tool_specs) do
    case Spec.normalize_many_strict(tool_specs) do
      {:ok, normalized_specs} ->
        Jason.encode!(normalized_specs)

      {:error, errors} ->
        raise ArgumentError, "invalid planned dynamic tool specs: #{inspect(errors)}"
    end
  end
end
