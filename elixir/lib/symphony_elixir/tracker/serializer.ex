defmodule SymphonyElixir.Tracker.Serializer do
  @moduledoc """
  Tracker serializer entrypoint for dynamic tool payloads.
  """

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Tracker.Error

  @spec error_payload(Error.t()) :: map()
  def error_payload(%Error{} = error), do: Serializer.error_payload(error)

  @spec public_error_details(map() | nil) :: map() | nil
  def public_error_details(details), do: Serializer.public_error_details(details)

  @spec json_safe_map(map()) :: map()
  def json_safe_map(map), do: Serializer.json_safe_map(map)

  @spec json_safe_value(term()) :: term()
  def json_safe_value(value), do: Serializer.json_safe_value(value)

  @spec json_safe_key(term()) :: String.t()
  def json_safe_key(key), do: Serializer.json_safe_key(key)

  @spec maybe_put(map(), String.t(), term()) :: map()
  def maybe_put(payload, key, value), do: Serializer.maybe_put(payload, key, value)
end
