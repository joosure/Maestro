defmodule SymphonyElixir.Agent.DynamicTool.Inventory.Renderer do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Inventory.{RenderOptions, ResolvedTool}

  @max_cell_length 240
  @max_note_length 1_000

  @spec render([ResolvedTool.t()], RenderOptions.raw()) :: String.t()
  def render(tools, opts) when is_list(tools) do
    options = RenderOptions.normalize(opts)

    case tools do
      [] ->
        empty_inventory()

      tools ->
        rows =
          tools
          |> resolved_tools()
          |> Enum.sort_by(&{sort_value(&1.capability), sort_value(&1.tool)})
          |> Enum.map_join("\n", &inventory_row(&1, options))

        if rows == "", do: empty_inventory(), else: rendered_inventory(rows, options)
    end
  end

  def render(_tools, _opts), do: empty_inventory()

  defp empty_inventory do
    """
    ## Typed Tool Inventory

    No typed tools are advertised for this session. Use provider skills only
    for context gathering; routine actions require canonical typed tools.
    """
    |> String.trim()
  end

  defp rendered_inventory(rows, %RenderOptions{} = options) do
    if RenderOptions.provider_callable?(options) do
      provider_note = markdown_text(RenderOptions.provider_callable_note(options), @max_note_length)
      provider_label = markdown_cell(RenderOptions.provider_callable_label(options))

      """
      ## Typed Tool Inventory

      Use these exact provider-facing callable tool names for routine
      actions. #{provider_note} Do not guess provider API fields, mutation
      names, CLI arguments, or alternate tool names for these capabilities.
      If a listed typed tool returns a validation or provider error, correct
      the typed tool arguments and retry that same typed tool. Do not switch to
      raw provider tools, helper CLIs, shell commands, or alternate tool names.

      | Capability | #{provider_label} | Runtime tool | Side effect | Source |
      | --- | --- | --- | --- | --- |
      #{rows}
      """
      |> String.trim()
    else
      """
      ## Typed Tool Inventory

      Use these exact runtime tool names for routine actions.
      Do not guess provider API fields, mutation names, CLI arguments, or
      alternate tool names for these capabilities.
      If a listed typed tool returns a validation or provider error, correct
      the typed tool arguments and retry that same typed tool. Do not switch to
      raw provider tools, helper CLIs, shell commands, or alternate tool names.

      | Capability | Runtime tool | Side effect | Source |
      | --- | --- | --- | --- |
      #{rows}
      """
      |> String.trim()
    end
  end

  defp inventory_row(%ResolvedTool{} = tool, %RenderOptions{} = options) do
    if RenderOptions.provider_callable?(options) do
      "| #{inline_code(tool.capability)} | #{inline_code(provider_callable_tool(tool, options))} | #{inline_code(tool.tool)} | #{inline_code(tool.side_effect)} | #{inline_code(tool.source_kind)} |"
    else
      "| #{inline_code(tool.capability)} | #{inline_code(tool.tool)} | #{inline_code(tool.side_effect)} | #{inline_code(tool.source_kind)} |"
    end
  end

  defp resolved_tools(tools), do: Enum.filter(tools, &match?(%ResolvedTool{}, &1))

  defp provider_callable_tool(%ResolvedTool{} = tool, %RenderOptions{} = options) do
    case RenderOptions.provider_callable_name(options) do
      callable_name when is_function(callable_name, 1) ->
        safe_callable_tool_name(callable_name, tool.tool)

      _callable_name ->
        tool.tool
    end
  end

  defp safe_callable_tool_name(callable_name, tool_name) do
    case callable_name.(tool_name) |> String.trim() do
      "" ->
        tool_name

      name ->
        name
    end
  rescue
    _reason -> tool_name
  catch
    _kind, _reason -> tool_name
  end

  defp inline_code(value) do
    value
    |> markdown_cell()
    |> String.replace("`", "'")
    |> then(&"`#{&1}`")
  end

  defp markdown_cell(value, max_length \\ @max_cell_length) do
    value
    |> markdown_text(max_length)
    |> String.replace("|", "\\|")
  end

  defp markdown_text(value, max_length) do
    value
    |> string_value()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> truncate(max_length)
  end

  defp truncate(value, max_length) when is_binary(value) and is_integer(max_length) do
    if String.length(value) > max_length do
      String.slice(value, 0, max_length) <> "..."
    else
      value
    end
  end

  defp string_value(value) when is_binary(value), do: value
  defp string_value(nil), do: ""
  defp string_value(value), do: inspect(value, limit: 20, printable_limit: 80)

  defp sort_value(value) when is_binary(value), do: value
  defp sort_value(_value), do: ""
end
