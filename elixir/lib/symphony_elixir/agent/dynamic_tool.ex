defmodule SymphonyElixir.Agent.DynamicTool do
  @moduledoc """
  Provider-neutral facade for agent dynamic tool capture and execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, Source}

  @type tool_context :: Context.t()
  @type tool_result :: Source.tool_result()

  @spec capture_context(keyword()) :: tool_context()
  def capture_context(opts \\ []) when is_list(opts), do: Context.from_opts(opts)

  @spec tool_specs(keyword()) :: [map()]
  def tool_specs(opts \\ []) when is_list(opts) do
    opts
    |> Context.from_opts()
    |> Context.tool_specs()
  end

  @spec execute(tool_context(), String.t() | nil, term(), keyword()) :: tool_result()
  def execute(tool_context, tool, arguments, opts \\ []) when is_map(tool_context) and is_list(opts) do
    source = Context.source(tool_context)
    source_context = Context.source_context(tool_context)

    Source.execute(
      source,
      source_context,
      tool,
      arguments,
      Keyword.put(opts, :tool_context, tool_context)
    )
  end
end
