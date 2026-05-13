defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Values do
  @moduledoc false

  @spec field_value(map(), String.t(), atom()) :: term()
  def field_value(map, string_key, atom_key) when is_map(map) do
    Map.get(map, string_key, Map.get(map, atom_key))
  end

  def field_value(_map, _string_key, _atom_key), do: nil

  @spec json_id(term()) :: term()
  def json_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> value
    end
  end

  def json_id(value), do: value

  @spec opaque_id(term()) :: String.t() | nil
  def opaque_id(nil), do: nil
  def opaque_id(""), do: nil
  def opaque_id(value) when is_binary(value), do: value
  def opaque_id(value) when is_integer(value), do: Integer.to_string(value)
  def opaque_id(value), do: to_string(value)

  @spec reply_id(term()) :: String.t() | nil
  def reply_id(nil), do: nil
  def reply_id(""), do: nil
  def reply_id("0"), do: nil
  def reply_id(0), do: nil
  def reply_id(value), do: opaque_id(value)

  @spec slice_page(list(), pos_integer(), pos_integer()) :: list()
  def slice_page(items, page, per_page) do
    Enum.slice(items, (page - 1) * per_page, per_page)
  end

  @spec expect_list(term(), atom()) :: {:ok, list()} | {:error, term()}
  def expect_list(payload, _context) when is_list(payload), do: {:ok, payload}
  def expect_list(payload, context), do: {:error, {:cnb_unknown_payload, context, payload}}

  @spec expect_map(term(), atom()) :: {:ok, map()} | {:error, term()}
  def expect_map(payload, _context) when is_map(payload), do: {:ok, payload}
  def expect_map(payload, context), do: {:error, {:cnb_unknown_payload, context, payload}}
end
