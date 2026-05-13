defmodule SymphonyWorkerDaemon.Protocol.Validation.Payload do
  @moduledoc false

  @spec size(String.t(), term(), pos_integer() | nil) :: :ok | {:error, term()}
  def size(_field, _payload, nil), do: :ok

  def size(field, payload, max_bytes) when is_binary(field) and is_integer(max_bytes) and max_bytes > 0 do
    case encoded_size(payload) do
      size when is_integer(size) and size <= max_bytes -> :ok
      size when is_integer(size) -> {:error, {:payload_too_large, field, size, max_bytes}}
      :invalid -> {:error, {:payload_invalid, field}}
    end
  end

  @spec limit(keyword(), atom(), pos_integer()) :: pos_integer() | nil
  def limit(opts, key, default) when is_list(opts) and is_integer(default) and default > 0 do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value > 0 -> value
      :infinity -> nil
      _value -> default
    end
  end

  @spec string_list(term()) :: [String.t()]
  def string_list(values) when is_list(values) do
    values
    |> Enum.map(&optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  def string_list(_values), do: []

  defp encoded_size(payload) when is_binary(payload), do: byte_size(payload)

  defp encoded_size(payload) do
    case Jason.encode(payload) do
      {:ok, encoded} -> byte_size(encoded)
      {:error, _reason} -> :invalid
    end
  end

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil
end
