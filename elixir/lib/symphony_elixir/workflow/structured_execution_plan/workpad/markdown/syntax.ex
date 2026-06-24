defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Syntax do
  @moduledoc """
  Markdown formatting primitives for structured-plan Workpad rendering.

  This module owns syntax tokens only. It does not read plan fields or decide
  rendering policy.
  """

  @line_separator "\n"
  @blank_line ""
  @heading_marker "#"
  @inline_code_marker "`"
  @list_marker "- "
  @checked_box "[x]"
  @unchecked_box "[ ]"
  @space " "
  @label_separator ": "
  @item_detail_prefix " - "
  @detail_separator ", "
  @count_separator ":"

  @spec heading(pos_integer(), String.t()) :: String.t()
  def heading(level, text) when is_integer(level) and level > 0 and is_binary(text) do
    String.duplicate(@heading_marker, level) <> @space <> text
  end

  @spec blank_line() :: String.t()
  def blank_line, do: @blank_line

  @spec inline_code(String.t()) :: String.t()
  def inline_code(text) when is_binary(text), do: @inline_code_marker <> text <> @inline_code_marker

  @spec task_checkbox(boolean()) :: String.t()
  def task_checkbox(true), do: @checked_box
  def task_checkbox(false), do: @unchecked_box

  @spec metadata_line(String.t(), String.t()) :: String.t()
  def metadata_line(label, inline_value) when is_binary(label) and is_binary(inline_value), do: label <> @label_separator <> inline_value

  @spec detail(String.t(), String.t()) :: String.t()
  def detail(label, inline_value) when is_binary(label) and is_binary(inline_value), do: label <> @label_separator <> inline_value

  @spec counted_value(String.t(), non_neg_integer()) :: String.t()
  def counted_value(label, count) when is_binary(label) and is_integer(count) and count >= 0, do: label <> @count_separator <> Integer.to_string(count)

  @spec join_details([String.t()]) :: String.t()
  def join_details(details) when is_list(details), do: Enum.join(details, @detail_separator)

  @spec task_item(boolean(), String.t(), String.t(), [String.t()]) :: String.t()
  def task_item(complete?, inline_item_id, title, details) when is_boolean(complete?) and is_binary(inline_item_id) and is_binary(title) and is_list(details) do
    list_item([
      task_checkbox(complete?),
      @space,
      inline_item_id,
      @space,
      title,
      @item_detail_prefix,
      join_details(details)
    ])
  end

  @spec list_item(iodata()) :: String.t()
  def list_item(content), do: IO.iodata_to_binary([@list_marker, content])

  @spec join_lines([String.t() | nil | [String.t() | nil]]) :: String.t()
  def join_lines(lines) when is_list(lines) do
    lines
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(@line_separator)
    |> Kernel.<>(@line_separator)
  end
end
