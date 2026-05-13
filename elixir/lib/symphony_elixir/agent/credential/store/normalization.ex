defmodule SymphonyElixir.Agent.Credential.Store.Normalization do
  @moduledoc false

  @spec normalize_attrs(keyword() | map()) :: map()
  def normalize_attrs(attrs) when is_list(attrs) do
    attrs
    |> Map.new()
    |> normalize_attrs()
  end

  def normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc -> Map.put(acc, to_string(key), value) end)
  end

  @spec normalize_provider_kind!(String.t()) :: String.t()
  def normalize_provider_kind!(provider_kind) when is_binary(provider_kind) do
    case String.trim(provider_kind) do
      "" -> raise ArgumentError, "agent provider kind must not be blank"
      normalized -> normalized
    end
  end

  @spec normalize_id!(String.t()) :: String.t()
  def normalize_id!(id) when is_binary(id) do
    case String.trim(id) do
      "" -> raise ArgumentError, "credential account id must not be blank"
      normalized -> normalized
    end
  end

  @spec future_iso?(String.t()) :: boolean()
  def future_iso?(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> DateTime.compare(timestamp, DateTime.utc_now()) == :gt
      _datetime -> false
    end
  end

  @spec normalize_datetime_string(term()) :: String.t() | nil
  def normalize_datetime_string(nil), do: nil
  def normalize_datetime_string(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  def normalize_datetime_string(value) when is_integer(value) and value > 0 do
    case DateTime.from_unix(value) do
      {:ok, timestamp} -> DateTime.to_iso8601(timestamp)
      _datetime -> Integer.to_string(value)
    end
  end

  def normalize_datetime_string(value) when is_binary(value) do
    value = String.trim(value)

    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} ->
        DateTime.to_iso8601(timestamp)

      _datetime ->
        case Integer.parse(value) do
          {unix_seconds, ""} -> normalize_datetime_string(unix_seconds)
          _parse -> if(value == "", do: nil, else: value)
        end
    end
  end

  def normalize_datetime_string(_value), do: nil

  @spec normalize_datetime(term()) :: DateTime.t() | nil
  def normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> timestamp
      _datetime -> nil
    end
  end

  def normalize_datetime(_value), do: nil

  @spec normalize_optional_string(term()) :: term()
  def normalize_optional_string(nil), do: nil

  def normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_optional_string(value), do: value

  @spec drop_nil_values(map()) :: map()
  def drop_nil_values(value) when is_map(value) do
    Enum.reduce(value, %{}, fn
      {_key, nil}, acc -> acc
      {key, nested}, acc -> Map.put(acc, key, nested)
    end)
  end

  @spec integer_value(term()) :: non_neg_integer()
  def integer_value(value) when is_integer(value) and value >= 0, do: value
  def integer_value(value) when is_float(value) and value >= 0, do: trunc(value)

  def integer_value(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {num, _rest} when num >= 0 -> num
      _parse -> 0
    end
  end

  def integer_value(_value), do: 0

  @spec maybe_integer_value(term()) :: non_neg_integer() | nil
  def maybe_integer_value(nil), do: nil
  def maybe_integer_value(value), do: integer_value(value)

  @spec positive_integer_value(term()) :: pos_integer() | nil
  def positive_integer_value(value) do
    case integer_value(value) do
      number when number > 0 -> number
      _number -> nil
    end
  end

  @spec now_iso() :: String.t()
  def now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
