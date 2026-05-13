defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.ToolEntries do
  @moduledoc false

  @spec from_specs([map()]) :: [{String.t(), map()}]
  def from_specs(tool_specs) when is_list(tool_specs) do
    {_seen, entries} =
      Enum.reduce(tool_specs, {%{}, []}, fn tool_spec, {seen, entries} ->
        base = filename_base(tool_spec)
        count = Map.get(seen, base, 0)
        filename = if count == 0, do: base <> ".ts", else: "#{base}_#{count + 1}.ts"
        {Map.put(seen, base, count + 1), [{filename, tool_spec} | entries]}
      end)

    Enum.reverse(entries)
  end

  defp filename_base(tool_spec) do
    tool_spec
    |> tool_name()
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "_")
    |> String.replace(~r/^[._-]+|[._-]+$/, "")
    |> case do
      "" -> "planned_tool"
      filename -> filename
    end
  end

  defp tool_name(%{"name" => name}) when is_binary(name), do: name
  defp tool_name(%{name: name}) when is_binary(name), do: name
  defp tool_name(_tool_spec), do: "planned_tool"
end
