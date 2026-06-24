defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Sanitizer do
  @moduledoc """
  Redaction and truncation helpers for provider-session events.
  """

  alias SymphonyElixir.Observability.Redaction

  @max_text_bytes 240
  @max_summary_bytes 512

  @spec bounded_string(String.t() | nil) :: String.t() | nil
  def bounded_string(nil), do: nil

  def bounded_string(value) when is_binary(value) do
    value
    |> Redaction.redact_string()
    |> String.trim()
    |> truncate(@max_text_bytes)
    |> case do
      "" -> nil
      text -> text
    end
  end

  @spec payload_summary(term()) :: String.t()
  def payload_summary(payload), do: Redaction.summarize(payload, @max_summary_bytes)

  @spec compact(map()) :: map()
  def compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] or value == %{} end)
  end

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes, do: value

  defp truncate(value, max_bytes) do
    value
    |> binary_part(0, max_bytes)
    |> valid_prefix()
    |> Kernel.<>("...<truncated>")
  end

  defp valid_prefix(value) do
    if String.valid?(value), do: value, else: value |> binary_part(0, byte_size(value) - 1) |> valid_prefix()
  end
end
