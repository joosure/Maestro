defmodule SymphonyElixir.Agent.ExecutionPlan.DynamicToolSource do
  @moduledoc """
  Explicit opt-in Dynamic Tool source for generic Agent execution-plan tools.

  The default composite tool source does not include this module. Tests and
  migration harnesses can inject it directly while the Agent-owned plan store
  and operator inspection surfaces mature.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Options, as: ToolOptions
  alias SymphonyElixir.Agent.ExecutionPlan.ToolExecutor

  @spec default_context(keyword()) :: map()
  def default_context(opts \\ []), do: ToolOptions.source_context(opts)

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: ToolContract.source_kind()

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    ToolExecutor.tool_specs(expose?: ToolOptions.expose?(source_context))
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(_source_context, _opts \\ []), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    ToolExecutor.execute(tool, arguments, ToolOptions.merge_source_context(opts, source_context))
  end

  def execute(_source_context, tool, _arguments, _opts), do: ToolExecutor.execute(tool, %{})
end
