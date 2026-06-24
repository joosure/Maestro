defmodule SymphonyElixir.AgentProvider.CodeBuddyCode.Tooling.ToolSpecs do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context

  @spec from_opts(keyword()) :: [map()]
  def from_opts(opts) when is_list(opts) do
    opts
    |> tool_context()
    |> Context.tool_specs()
    |> Enum.filter(&valid?/1)
  end

  @spec tool_context(keyword()) :: Context.t()
  def tool_context(opts) when is_list(opts) do
    case Keyword.get(opts, :tool_context) do
      %Context{} ->
        Context.from_opts(opts)

      %{"tool_specs" => tool_specs} when is_list(tool_specs) ->
        Context.from_opts(opts)

      _context ->
        Context.empty()
    end
  end

  defp valid?(%{"name" => name}) when is_binary(name) and name != "", do: true
  defp valid?(%{name: name}) when is_binary(name) and name != "", do: true
  defp valid?(_tool_spec), do: false
end
