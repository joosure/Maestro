defmodule SymphonyElixir.Tracker.Tapd.CommentCodec.DescriptionDecoder do
  @moduledoc false

  @block_tags ~w[h1 h2 h3 h4 h5 h6 p div ul ol pre]
  @html_fragment_pattern ~r/<[a-zA-Z][^>]*>/

  @spec decode(String.t()) :: String.t()
  def decode(description) when is_binary(description) do
    trimmed = String.trim(description)

    cond do
      trimmed == "" ->
        description

      not html_fragment?(trimmed) ->
        description

      true ->
        case Floki.parse_fragment(trimmed) do
          {:ok, nodes} ->
            nodes
            |> nodes_to_markdown(0)
            |> Enum.reject(&blank_markdown_block?/1)
            |> join_markdown_blocks()
            |> String.trim()

          {:error, _reason} ->
            description
        end
    end
  end

  defp nodes_to_markdown(nodes, indent) when is_list(nodes) do
    Enum.flat_map(nodes, &node_to_markdown_blocks(&1, indent))
  end

  defp node_to_markdown_blocks(text, _indent) when is_binary(text) do
    case normalize_block_text(text) do
      "" -> []
      content -> [content]
    end
  end

  defp node_to_markdown_blocks({"h1", _attrs, children}, _indent), do: ["# " <> inline_to_markdown(children)]
  defp node_to_markdown_blocks({"h2", _attrs, children}, _indent), do: ["## " <> inline_to_markdown(children)]
  defp node_to_markdown_blocks({"h3", _attrs, children}, _indent), do: ["### " <> inline_to_markdown(children)]
  defp node_to_markdown_blocks({"h4", _attrs, children}, _indent), do: ["#### " <> inline_to_markdown(children)]
  defp node_to_markdown_blocks({"h5", _attrs, children}, _indent), do: ["##### " <> inline_to_markdown(children)]
  defp node_to_markdown_blocks({"h6", _attrs, children}, _indent), do: ["###### " <> inline_to_markdown(children)]

  defp node_to_markdown_blocks({"pre", _attrs, children}, _indent) do
    [pre_to_markdown(children)]
  end

  defp node_to_markdown_blocks({"ul", _attrs, children}, indent) do
    [list_to_markdown(children, indent)]
  end

  defp node_to_markdown_blocks({"ol", _attrs, children}, indent) do
    [list_to_markdown(children, indent)]
  end

  defp node_to_markdown_blocks({"p", _attrs, children}, _indent) do
    case String.trim(inline_to_markdown(children)) do
      "" -> []
      content -> [content]
    end
  end

  defp node_to_markdown_blocks({"div", _attrs, children}, indent) do
    if block_container?(children) do
      nodes_to_markdown(children, indent)
    else
      case String.trim(inline_to_markdown(children)) do
        "" -> []
        content -> [content]
      end
    end
  end

  defp node_to_markdown_blocks({_tag, _attrs, children}, indent), do: nodes_to_markdown(children, indent)

  defp list_to_markdown(children, indent) do
    children
    |> Enum.filter(&list_item_node?/1)
    |> Enum.map_join("\n", &list_item_to_markdown(&1, indent))
  end

  defp list_item_to_markdown({"li", _attrs, children}, indent) do
    {inline_children, nested_children} = split_list_item_children(children, [], [])
    prefix = String.duplicate(" ", indent) <> "- "
    line = prefix <> String.trim(inline_to_markdown(inline_children))

    nested =
      nested_children
      |> Enum.flat_map(&node_to_markdown_blocks(&1, indent + 2))
      |> Enum.reject(&blank_markdown_block?/1)
      |> Enum.join("\n")

    case String.trim(nested) do
      "" -> line
      nested_markdown -> line <> "\n" <> nested_markdown
    end
  end

  defp split_list_item_children([], inline_children, nested_children),
    do: {Enum.reverse(inline_children), Enum.reverse(nested_children)}

  defp split_list_item_children([{tag, _attrs, _children} = node | rest], inline_children, nested_children)
       when tag in ["ul", "ol"] do
    split_list_item_children(rest, inline_children, [node | nested_children])
  end

  defp split_list_item_children([node | rest], inline_children, nested_children) do
    split_list_item_children(rest, [node | inline_children], nested_children)
  end

  defp pre_to_markdown(children) do
    {language, code} =
      case Enum.find(children, &code_node?/1) do
        {"code", attrs, code_children} ->
          {language_from_attrs(attrs), Floki.text(code_children, sep: "")}

        _ ->
          {nil, Floki.text(children, sep: "")}
      end

    opening =
      case language do
        nil -> "```"
        normalized -> "```" <> normalized
      end

    [opening, code, "```"]
    |> Enum.join("\n")
  end

  defp inline_to_markdown(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &inline_node_to_markdown/1)
  end

  defp inline_node_to_markdown(text) when is_binary(text), do: normalize_inline_text(text)
  defp inline_node_to_markdown({"br", _attrs, _children}), do: "\n"

  defp inline_node_to_markdown({"a", attrs, children}) do
    href = attr_value(attrs, "href")
    label = inline_to_markdown(children) |> String.trim()

    cond do
      is_nil(href) or href == "" ->
        label

      label == "" ->
        href

      label == href ->
        href

      true ->
        "[#{label}](#{href})"
    end
  end

  defp inline_node_to_markdown({"code", _attrs, children}) do
    "`" <> Floki.text(children, sep: "") <> "`"
  end

  defp inline_node_to_markdown({tag, _attrs, children}) when tag in ["strong", "b"] do
    "**" <> inline_to_markdown(children) <> "**"
  end

  defp inline_node_to_markdown({tag, _attrs, children}) when tag in ["em", "i"] do
    "*" <> inline_to_markdown(children) <> "*"
  end

  defp inline_node_to_markdown({_tag, _attrs, children}), do: inline_to_markdown(children)

  defp block_container?(children) do
    Enum.any?(children, fn
      {tag, _attrs, _children} -> tag in @block_tags
      _node -> false
    end)
  end

  defp code_node?({"code", _attrs, _children}), do: true
  defp code_node?(_node), do: false

  defp list_item_node?({"li", _attrs, _children}), do: true
  defp list_item_node?(_node), do: false

  defp language_from_attrs(attrs) do
    attrs
    |> attr_value("class")
    |> normalize_language_class()
  end

  defp normalize_language_class(nil), do: nil

  defp normalize_language_class(class_name) when is_binary(class_name) do
    class_name
    |> String.split()
    |> Enum.find_value(fn
      "language-" <> language -> language
      _class -> nil
    end)
  end

  defp attr_value(attrs, key) when is_list(attrs) and is_binary(key) do
    attrs
    |> Enum.find_value(fn
      {^key, value} -> value
      _attr -> nil
    end)
  end

  defp html_fragment?(value) when is_binary(value), do: String.match?(value, @html_fragment_pattern)

  defp blank_markdown_block?(value) when is_binary(value), do: String.trim(value) == ""

  defp join_markdown_blocks([]), do: ""
  defp join_markdown_blocks([block]), do: block

  defp join_markdown_blocks([first | rest]) do
    Enum.reduce(rest, first, fn block, acc ->
      acc <> separator_for_markdown_blocks(acc, block) <> block
    end)
  end

  defp separator_for_markdown_blocks(acc, block) when is_binary(acc) and is_binary(block) do
    previous_block =
      acc
      |> String.split("\n\n")
      |> List.last()
      |> to_string()

    cond do
      heading_level(previous_block) >= 3 and list_markdown_block?(block) ->
        "\n"

      true ->
        "\n\n"
    end
  end

  defp heading_level(value) when is_binary(value) do
    case Regex.run(~r/^(#+)\s/, value) do
      [_, hashes] -> String.length(hashes)
      _match -> 0
    end
  end

  defp list_markdown_block?(value) when is_binary(value), do: String.starts_with?(String.trim_leading(value), "- ")

  defp normalize_block_text(text) when is_binary(text) do
    text
    |> String.replace("\u00A0", " ")
    |> String.trim()
  end

  defp normalize_inline_text(text) when is_binary(text) do
    String.replace(text, "\u00A0", " ")
  end
end
