defmodule SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Text do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Access

  @spec sanitize_ansi_and_control_bytes(String.t()) :: String.t()
  def sanitize_ansi_and_control_bytes(value) when is_binary(value) do
    value
    |> String.replace(~r/\x1B\[[0-9;]*[A-Za-z]/, "")
    |> String.replace(~r/\x1B./, "")
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
  end

  @spec format_error_value(term()) :: String.t()
  def format_error_value(%{"message" => message}) when is_binary(message), do: message
  def format_error_value(%{message: message}) when is_binary(message), do: message
  def format_error_value(error), do: inspect(error, limit: 10)

  @spec format_reason(term()) :: String.t()
  def format_reason(message) when is_map(message) do
    case Access.map_value(message, ["reason", :reason]) do
      nil ->
        message
        |> inspect(limit: 10)
        |> inline_text()

      reason ->
        format_error_value(reason)
    end
  end

  def format_reason(other), do: format_error_value(other)

  @spec format_item_type(term()) :: String.t()
  def format_item_type(nil), do: "item"

  def format_item_type(type) when is_binary(type) do
    type
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1 \\2")
    |> String.replace("_", " ")
    |> String.replace("/", " ")
    |> String.downcase()
    |> String.trim()
  end

  def format_item_type(type), do: to_string(type)

  @spec format_status(term()) :: String.t() | nil
  def format_status(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.downcase()
    |> String.trim()
  end

  def format_status(_status), do: nil

  @spec short_id(term()) :: String.t() | nil
  def short_id(id) when is_binary(id) and byte_size(id) > 12, do: String.slice(id, 0, 12)
  def short_id(id) when is_binary(id), do: id
  def short_id(_id), do: nil

  @spec append_if_present([term()], term()) :: [term()]
  def append_if_present(list, value) when is_binary(value) and value != "", do: list ++ [value]
  def append_if_present(list, _value), do: list

  @spec inline_text(term()) :: String.t()
  def inline_text(text) when is_binary(text) do
    text
    |> String.replace("\n", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(80)
  end

  def inline_text(other), do: other |> to_string() |> inline_text()

  @spec parse_integer(term()) :: integer() | nil
  def parse_integer(value) when is_integer(value), do: value

  def parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  def parse_integer(_value), do: nil

  @spec format_count(term()) :: String.t()
  def format_count(nil), do: "0"

  def format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> group_thousands()
  end

  def format_count(value) when is_binary(value) do
    value
    |> String.trim()
    |> Integer.parse()
    |> case do
      {number, ""} -> group_thousands(Integer.to_string(number))
      _ -> value
    end
  end

  def format_count(value), do: to_string(value)

  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(value, max) when byte_size(value) > max do
    value |> String.slice(0, max) |> Kernel.<>("...")
  end

  def truncate(value, _max), do: value

  defp group_thousands(value) when is_binary(value) do
    sign = if String.starts_with?(value, "-"), do: "-", else: ""
    unsigned = if sign == "", do: value, else: String.slice(value, 1, String.length(value) - 1)

    unsigned
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> prepend(sign)
  end

  defp prepend("", value), do: value
  defp prepend(prefix, value), do: prefix <> value
end
