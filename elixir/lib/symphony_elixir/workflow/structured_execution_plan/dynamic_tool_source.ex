defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource do
  @moduledoc """
  Explicit opt-in Dynamic Tool source for internal structured plan tools.

  The default composite tool source does not include this module. Tests and
  local smoke harnesses can inject it directly when they need Phase 3 plan
  tools without granting repo or tracker mutation authority.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Aliases, as: ToolAliases
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor

  @spec default_context(keyword()) :: map()
  def default_context(opts \\ []), do: Options.context(opts)

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: "workflow"

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    canonical_specs = ToolExecutor.tool_specs()

    if Options.enabled?(source_context) do
      alias_specs = ToolAliases.provider_alias_specs(canonical_specs, Options.provider_contexts(source_context))
      canonical_specs ++ alias_specs
    else
      []
    end
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(_source_context, _opts \\ []), do: %{}

  @spec canonical_tool(term(), String.t() | nil) :: String.t() | nil
  def canonical_tool(source_context, tool) when is_map(source_context), do: canonical_tool_name(tool, source_context)
  def canonical_tool(_source_context, tool), do: canonical_tool_name(tool, %{})

  @spec execute(term(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    canonical_tool = canonical_tool_name(tool, source_context)

    if Options.enabled?(source_context, opts) do
      ToolExecutor.execute(
        canonical_tool,
        arguments,
        opts
        |> maybe_put(:server, Map.get(source_context, :server))
        |> maybe_put(:updated_at, Map.get(source_context, :updated_at))
      )
    else
      ToolExecutor.execute("__structured_execution_plan_disabled__", %{})
    end
  end

  def execute(_source_context, tool, _arguments, _opts), do: ToolExecutor.execute(canonical_tool_name(tool, %{}), %{})

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp canonical_tool_name(tool, source_context) do
    case ToolAliases.canonical_name(tool, Options.provider_contexts(source_context)) do
      {:ok, canonical_tool} -> canonical_tool
      :error -> tool
    end
  end
end
