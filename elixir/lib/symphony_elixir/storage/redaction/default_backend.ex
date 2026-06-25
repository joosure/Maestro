defmodule SymphonyElixir.Storage.Redaction.DefaultBackend do
  @moduledoc false

  @behaviour SymphonyElixir.Storage.Redaction

  alias SymphonyElixir.Observability.Redaction, as: ObservabilityRedaction

  @redacted "[REDACTED]"
  @sensitive_key_patterns [
    ~r/password/i,
    ~r/passphrase/i,
    ~r/secret/i,
    ~r/token/i,
    ~r/api[_-]?key/i,
    ~r/credential/i,
    ~r/authorization/i
  ]

  @impl true
  def redact(value, _opts), do: redact_value(value)

  defp redact_value(%{__struct__: module} = struct) when is_atom(module) do
    redacted_fields =
      struct
      |> Map.from_struct()
      |> redact_value()

    struct(module, redacted_fields)
  rescue
    _reason -> struct
  end

  defp redact_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key) do
        {key, @redacted}
      else
        {key, redact_value(value)}
      end
    end)
  end

  defp redact_value(list) when is_list(list), do: Enum.map(list, &redact_value/1)

  defp redact_value({key, value}) do
    if sensitive_key?(key) do
      {key, @redacted}
    else
      {key, redact_value(value)}
    end
  end

  defp redact_value(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> redact_value() |> List.to_tuple()
  defp redact_value(value) when is_binary(value), do: ObservabilityRedaction.redact_string(value)
  defp redact_value(value), do: value

  defp sensitive_key?(key) when is_atom(key), do: key |> Atom.to_string() |> sensitive_key?()

  defp sensitive_key?(key) when is_binary(key) do
    Enum.any?(@sensitive_key_patterns, &Regex.match?(&1, key))
  end

  defp sensitive_key?(_key), do: false
end
