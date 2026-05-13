defmodule SymphonyWorkerDaemon.Protocol.Request do
  @moduledoc false

  @spec input(iodata(), keyword(), String.t()) :: map()
  def input(data, opts, protocol_version) when is_list(opts) and is_binary(protocol_version) do
    %{
      "protocol_version" => protocol_version,
      "request_id" => request_id(opts),
      "input" => IO.iodata_to_binary(data),
      "encoding" => "utf-8"
    }
  end

  @spec stop(keyword(), String.t()) :: map()
  def stop(opts, protocol_version) when is_list(opts) and is_binary(protocol_version) do
    request_id = request_id(opts)

    %{
      "protocol_version" => protocol_version,
      "request_id" => request_id,
      "idempotency_key" => string_value(opts, :idempotency_key) || request_id,
      "reason" => string_value(opts, :reason) || "symphony_stop"
    }
  end

  @spec cleanup(keyword(), String.t()) :: map()
  def cleanup(opts, protocol_version) when is_list(opts) and is_binary(protocol_version) do
    request_id = request_id(opts)

    %{
      "protocol_version" => protocol_version,
      "request_id" => request_id,
      "idempotency_key" => string_value(opts, :idempotency_key) || request_id
    }
  end

  defp request_id(opts) do
    string_value(opts, :request_id) || Ecto.UUID.generate()
  end

  defp string_value(opts, key) when is_list(opts) do
    opts
    |> Keyword.get(key)
    |> optional_string()
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
