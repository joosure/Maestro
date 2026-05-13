defmodule SymphonyElixir.Agent.DynamicTool.Serializer do
  @moduledoc """
  JSON-safe serialization helpers for dynamic tool provider boundaries.
  """

  @spec error_payload(term()) :: map()
  def error_payload(%{__struct__: _struct} = error) do
    %{
      "message" => Map.get(error, :message) || "Dynamic tool execution failed.",
      "code" => error |> Map.get(:code, :unknown) |> to_string()
    }
    |> maybe_put("status", detail_value(Map.get(error, :details), "status"))
    |> maybe_put("body", detail_value(Map.get(error, :details), "body"))
    |> maybe_put("details", public_error_details(Map.get(error, :details)))
    |> maybe_put("reason", detail_value(Map.get(error, :details), "reason") && inspect(detail_value(Map.get(error, :details), "reason")))
  end

  def error_payload(reason) do
    %{
      "message" => "Dynamic tool execution failed.",
      "reason" => inspect(reason)
    }
  end

  @spec public_error_details(map() | nil) :: map() | nil
  def public_error_details(details) when is_map(details) do
    details
    |> Map.drop([
      :source_reason,
      "source_reason",
      :status,
      "status",
      :body,
      "body",
      :reason,
      "reason"
    ])
    |> json_safe_map()
    |> case do
      sanitized when map_size(sanitized) == 0 -> nil
      sanitized -> sanitized
    end
  end

  def public_error_details(_details), do: nil

  @spec json_safe_map(map()) :: map()
  def json_safe_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {json_safe_key(key), json_safe_value(value)} end)
  end

  @spec json_safe_value(term()) :: term()
  def json_safe_value(%{__struct__: _struct, provider: provider, operation: operation, code: code, message: message} = error) do
    %{
      "provider" => provider,
      "operation" => to_string(operation),
      "code" => to_string(code),
      "message" => message,
      "retryable" => Map.get(error, :retryable?, false)
    }
    |> maybe_put("details", public_error_details(Map.get(error, :details)))
  end

  def json_safe_value(%_{} = value), do: inspect(value)
  def json_safe_value(map) when is_map(map), do: json_safe_map(map)
  def json_safe_value(list) when is_list(list), do: Enum.map(list, &json_safe_value/1)
  def json_safe_value(value) when is_boolean(value) or is_nil(value), do: value
  def json_safe_value(value) when is_atom(value), do: Atom.to_string(value)
  def json_safe_value(value) when is_tuple(value), do: inspect(value)
  def json_safe_value(value), do: value

  @spec json_safe_key(term()) :: String.t()
  def json_safe_key(key) when is_binary(key), do: key
  def json_safe_key(key) when is_atom(key), do: Atom.to_string(key)
  def json_safe_key(key) when is_integer(key), do: Integer.to_string(key)
  def json_safe_key(key), do: inspect(key)

  @spec maybe_put(map(), String.t(), term()) :: map()
  def maybe_put(payload, _key, nil), do: payload
  def maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp detail_value(details, key) when is_map(details) and is_binary(key) do
    Map.get(details, key) || Map.get(details, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(details, key)
  end

  defp detail_value(_details, _key), do: nil
end
