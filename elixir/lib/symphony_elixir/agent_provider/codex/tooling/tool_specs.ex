defmodule SymphonyElixir.AgentProvider.Codex.Tooling.ToolSpecs do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context

  @spec from_opts(keyword()) :: [map()]
  def from_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :tool_context) do
      %Context{} ->
        opts
        |> Context.from_opts()
        |> Context.tool_specs()
        |> Enum.filter(&valid?/1)

      %{"tool_specs" => tool_specs} when is_list(tool_specs) ->
        opts
        |> Context.from_opts()
        |> Context.tool_specs()
        |> Enum.filter(&valid?/1)

      _context ->
        []
    end
  end

  defp valid?(%{"name" => name}) when is_binary(name) and name != "", do: true
  defp valid?(%{name: name}) when is_binary(name) and name != "", do: true
  defp valid?(_tool_spec), do: false
end
