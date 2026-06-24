defmodule SymphonyElixir.Tracker.Linear.ToolExecutor do
  @moduledoc """
  Executes Linear typed Dynamic Tool requests.

  Raw Linear GraphQL is intentionally not exposed as an agent Dynamic Tool.
  GraphQL details are owned by typed tool handlers so agents use stable
  workflow capabilities instead of provider schema guesses.
  """

  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response
  alias SymphonyElixir.Tracker.Linear.ToolExecutor.TypedTools

  @spec tool_specs() :: [map()]
  def tool_specs, do: TypedTools.tool_specs()

  @spec tool_specs(map()) :: [map()]
  def tool_specs(_tracker), do: tool_specs()

  @spec supported_tool_names() :: [String.t()]
  def supported_tool_names, do: Enum.map(tool_specs(), &Map.fetch!(&1, "name"))

  @spec supported_tool_names(map()) :: [String.t()]
  def supported_tool_names(_tracker), do: supported_tool_names()

  @spec execute(map(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute(tracker, tool, arguments, opts)
      when is_map(tracker) and is_binary(tool) and is_list(opts) do
    if TypedTools.typed_tool?(tool) do
      TypedTools.execute(tracker, tool, arguments, opts)
    else
      unsupported_tool(tracker)
    end
  end

  def execute(_tracker, _tool, _arguments, _opts) do
    unsupported_tool()
  end

  defp unsupported_tool do
    {:failure,
     %{
       "error" => %{
         "code" => EventContract.unsupported_tool(),
         "message" => "Unsupported Linear dynamic tool.",
         Response.supported_tools_key() => supported_tool_names()
       }
     }}
  end

  defp unsupported_tool(tracker) when is_map(tracker) do
    {:failure,
     %{
       "error" => %{
         "code" => EventContract.unsupported_tool(),
         "message" => "Unsupported Linear dynamic tool.",
         Response.supported_tools_key() => supported_tool_names(tracker)
       }
     }}
  end
end
