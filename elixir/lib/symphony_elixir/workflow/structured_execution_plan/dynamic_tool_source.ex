defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource do
  @moduledoc """
  Explicit opt-in Dynamic Tool source for internal structured plan tools.

  The default composite tool source does not include this module. Tests and
  local smoke harnesses can inject it directly when they need Phase 3 plan
  tools without granting repo or tracker mutation authority.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor

  @spec default_context(keyword()) :: map()
  def default_context(opts \\ []) do
    %{
      server: Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store),
      provider_aliases: Keyword.get(opts, :structured_execution_plan_provider_aliases, [])
    }
  end

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: "workflow"

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    ToolExecutor.tool_specs(provider_aliases: Map.get(source_context, :provider_aliases, []))
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(_source_context, _opts \\ []), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    ToolExecutor.execute(
      tool,
      arguments,
      opts
      |> maybe_put(:server, Map.get(source_context, :server))
      |> maybe_put(:updated_at, Map.get(source_context, :updated_at))
    )
  end

  def execute(_source_context, tool, _arguments, _opts), do: ToolExecutor.execute(tool, %{})

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
