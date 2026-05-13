defmodule SymphonyElixir.Tracker.Tapd.CommentCodec.DescriptionEncoder do
  @moduledoc false

  @html_fragment_pattern ~r/<[a-zA-Z][^>]*>/
  @heading_pattern ~r/^(#+)\s+(.+)$/
  @list_pattern ~r/^(\s*)- (.+)$/
  @fenced_code_pattern ~r/^```([A-Za-z0-9_-]+)?\s*$/
  @markdown_link_pattern ~r/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/
  @inline_code_pattern ~r/`([^`]+)`/
  @autolink_pattern ~r{https?://[^\s<]+}

  @spec encode(String.t()) :: String.t()
  def encode(description) when is_binary(description) do
    trimmed = String.trim(description)

    cond do
      trimmed == "" ->
        description

      html_fragment?(trimmed) ->
        description

      true ->
        render_markdown(description)
    end
  end

  defp render_markdown(markdown) do
    markdown
    |> String.split(~r/\r\n|\n/, trim: false)
    |> render_blocks([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp render_blocks([], acc), do: acc

  defp render_blocks([line | rest], acc) do
    cond do
      blank_line?(line) ->
        render_blocks(rest, acc)

      fenced_code_start?(line) ->
        {html, remaining} = render_fenced_code(line, rest)
        render_blocks(remaining, [html | acc])

      heading_line?(line) ->
        {html, remaining} = render_heading(line, rest)
        render_blocks(remaining, [html | acc])

      list_line?(line) ->
        {html, remaining} = render_list_block([line | rest])
        render_blocks(remaining, [html | acc])

      true ->
        {html, remaining} = render_paragraph([line | rest])
        render_blocks(remaining, [html | acc])
    end
  end

  defp render_fenced_code(first_line, lines) do
    [_, language] = Regex.run(@fenced_code_pattern, first_line)
    {body_lines, remaining} = take_until_fence(lines, [])
    code = Enum.join(body_lines, "\n")

    language_attr =
      case normalize_language(language) do
        nil -> ""
        normalized -> ~s( class="language-#{escape_html(normalized)}")
      end

    html = "<pre><code#{language_attr}>#{escape_html(code)}</code></pre>"
    {html, remaining}
  end

  defp take_until_fence([], acc), do: {Enum.reverse(acc), []}

  defp take_until_fence([line | rest], acc) do
    if String.starts_with?(line, "```") do
      {Enum.reverse(acc), rest}
    else
      take_until_fence(rest, [line | acc])
    end
  end

  defp render_heading(line, rest) do
    [_, hashes, content] = Regex.run(@heading_pattern, line)
    level = hashes |> String.length() |> min(6)
    html = "<h#{level}>#{render_inline(String.trim(content))}</h#{level}>"
    {html, rest}
  end

  defp render_list_block(lines) do
    {list_lines, remaining} = Enum.split_while(lines, &list_line?/1)

    items =
      Enum.map(list_lines, fn line ->
        [_, indent, text] = Regex.run(@list_pattern, line)
        %{indent: String.length(indent), text: String.trim_trailing(text)}
      end)

    {html, []} = render_list(items, hd(items).indent)
    {html, remaining}
  end

  defp render_list(items, current_indent) do
    {rendered_items, remaining} = render_list_items(items, current_indent, [])
    {"<ul>" <> Enum.join(Enum.reverse(rendered_items)) <> "</ul>", remaining}
  end

  defp render_list_items([], _indent, acc), do: {acc, []}

  defp render_list_items([%{indent: indent} = item | rest], current_indent, acc) when indent < current_indent,
    do: {acc, [item | rest]}

  defp render_list_items([%{indent: indent} = item | rest], current_indent, acc) when indent > current_indent,
    do: render_list_items(rest, current_indent, ["<li>#{render_inline(item.text)}</li>" | acc])

  defp render_list_items([%{text: text} | rest], current_indent, acc) do
    {nested_html, remaining} =
      case rest do
        [%{indent: next_indent} | _] when next_indent > current_indent ->
          render_list(rest, next_indent)

        _ ->
          {"", rest}
      end

    rendered_item = "<li>" <> render_inline(text) <> nested_html <> "</li>"
    render_list_items(remaining, current_indent, [rendered_item | acc])
  end

  defp render_paragraph(lines) do
    {paragraph_lines, remaining} =
      Enum.split_while(lines, fn line ->
        not blank_line?(line) and not fenced_code_start?(line) and not heading_line?(line) and not list_line?(line)
      end)

    paragraph =
      paragraph_lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    {"<p>" <> render_inline(paragraph) <> "</p>", remaining}
  end

  defp render_inline(text) when is_binary(text) do
    {with_link_tokens, link_tokens} =
      collect_tokens(text, @markdown_link_pattern, fn [_, label, url] ->
        ~s(<a href="#{escape_html(url)}" target="_blank" rel="noreferrer noopener">#{render_inline(label)}</a>)
      end)

    {with_code_tokens, code_tokens} =
      collect_tokens(with_link_tokens, @inline_code_pattern, fn [_, code] ->
        "<code>" <> escape_html(code) <> "</code>"
      end)

    with_code_tokens
    |> escape_html()
    |> autolink_urls()
    |> restore_tokens(code_tokens)
    |> restore_tokens(link_tokens)
  end

  defp collect_tokens(text, regex, renderer) do
    Regex.scan(regex, text)
    |> Enum.with_index()
    |> Enum.reduce({text, []}, fn {captures, index}, {acc_text, acc_tokens} ->
      [fragment | _rest] = captures
      token = "__SYMPHONY_TAPD_TOKEN_#{index}_#{String.length(fragment)}__"
      html = renderer.(captures)
      {String.replace(acc_text, fragment, token, global: false), [{token, html} | acc_tokens]}
    end)
  end

  defp autolink_urls(text) do
    Regex.replace(@autolink_pattern, text, fn url ->
      ~s(<a href="#{escape_html(url)}" target="_blank" rel="noreferrer noopener">#{escape_html(url)}</a>)
    end)
  end

  defp restore_tokens(text, tokens) do
    Enum.reduce(tokens, text, fn {token, html}, acc -> String.replace(acc, token, html) end)
  end

  defp normalize_language(language) when is_binary(language) do
    case String.trim(language) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp html_fragment?(value) when is_binary(value), do: String.match?(value, @html_fragment_pattern)

  defp blank_line?(line) when is_binary(line), do: String.trim(line) == ""
  defp fenced_code_start?(line) when is_binary(line), do: String.match?(line, @fenced_code_pattern)
  defp heading_line?(line) when is_binary(line), do: String.match?(line, @heading_pattern)
  defp list_line?(line) when is_binary(line), do: String.match?(line, @list_pattern)

  defp escape_html(value) when is_binary(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
