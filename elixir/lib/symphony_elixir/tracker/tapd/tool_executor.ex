defmodule SymphonyElixir.Tracker.Tapd.ToolExecutor do
  @moduledoc """
  Executes TAPD typed dynamic tool requests.
  """

  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response
  alias SymphonyElixir.Tracker.Tapd.ToolExecutor.TypedTools

  @spec tool_specs() :: [map()]
  def tool_specs, do: TypedTools.tool_specs()

  @spec supported_tool_names() :: [String.t()]
  def supported_tool_names, do: Enum.map(tool_specs(), &Map.fetch!(&1, "name"))

  @spec execute(map(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute(tracker, tool, arguments, opts)
      when is_map(tracker) and is_list(opts) do
    if TypedTools.typed_tool?(tool) do
      TypedTools.execute(tracker, tool, arguments, opts)
    else
      {:failure, unsupported_tool(supported_tool_names())}
    end
  end

  def execute(_tracker, _tool, _arguments, _opts),
    do: {:failure, unsupported_tool(supported_tool_names())}

  defp unsupported_tool(supported_tools) when is_list(supported_tools) do
    %{
      "error" => %{
        "code" => EventContract.unsupported_tool(),
        "message" => "Unsupported TAPD dynamic tool.",
        Response.supported_tools_key() => supported_tools
      }
    }
  end
end
