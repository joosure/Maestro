defmodule SymphonyElixir.Agent.DynamicTool do
  @moduledoc """
  Provider-neutral facade for agent dynamic tool capture and execution.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, EventContract, ExecutionGuard, Source}
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.ErrorPayload, as: ExecutionGuardErrorPayload
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

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
    tool_context = Context.normalize(tool_context)
    source = Context.source(tool_context)
    source_context = Context.source_context(tool_context)
    executable_tool = Source.canonical_tool(source, source_context, tool)

    if Context.tool_enabled?(tool_context, tool) do
      case ExecutionGuard.ensure_authoritative_typed_tool(tool_context, executable_tool) do
        :ok ->
          Source.execute(
            source,
            source_context,
            executable_tool,
            arguments,
            Keyword.put(opts, :tool_context, tool_context)
          )

        {:error, decision} ->
          {:failure, ExecutionGuardErrorPayload.from_decision(decision)}
      end
    else
      {:failure,
       Response.error_payload(
         EventContract.unsupported_tool(),
         "Unsupported dynamic tool: #{inspect(tool)}.",
         %{Response.supported_tools_key() => supported_tool_names(tool_context)}
       )}
    end
  end

  defp supported_tool_names(tool_context) do
    tool_context
    |> Context.tool_specs()
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) -> [name]
      _tool_spec -> []
    end)
  end
end
