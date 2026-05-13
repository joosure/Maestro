defmodule SymphonyElixir.Tracker.DynamicToolSource do
  @moduledoc """
  Dynamic tool source backed by the configured issue tracker facade.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig

  @spec default_context(keyword()) :: TrackerConfig.t()
  def default_context(_opts \\ []), do: TrackerConfig.current!()

  @spec kind(term()) :: String.t() | nil
  def kind(%{kind: kind}) when is_binary(kind), do: kind
  def kind(%{"kind" => kind}) when is_binary(kind), do: kind
  def kind(_source_context), do: nil

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    Tracker.dynamic_tools(source_context)
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(source_context, opts \\ [])

  def environment(source_context, _opts) when is_map(source_context) do
    Tracker.tool_environment(source_context)
  end

  def environment(_source_context, _opts), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: Tracker.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    Tracker.execute_dynamic_tool(source_context, tool, arguments, opts)
  end

  def execute(_source_context, _tool, _arguments, _opts) do
    {:error, :dynamic_tool_source_context_unavailable}
  end
end
