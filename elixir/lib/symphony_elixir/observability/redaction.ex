defmodule SymphonyElixir.Observability.Redaction do
  @moduledoc """
  Shared helpers for redacting sensitive values before they reach logs or observability payloads.
  """

  @redacted "[REDACTED]"
  @default_summary_bytes 512
  @summary_bytes_key {__MODULE__, :summary_max_bytes}
  @sensitive_key_fragments ~w[
    apikey
    apisecret
    authorization
    password
    secret
    bearer
    cookie
    credential
    accesskey
    secretkey
  ]

  @bearer_like_value ~r/\b(Bearer|Basic)\s+[A-Za-z0-9+\/=._:-]+\b/i
  @env_assignment ~r/\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY|API_SECRET))=([^\s]+)/u
  @plain_assignment ~r/\b((?:api[_-]?key|api[_-]?secret|authorization|password|token|secret|cookie|credential|access[_-]?key|secret[_-]?key)\s*[:=]\s*)([^\s,;]+)/iu
  @quoted_assignment ~r/((?:api[_-]?key|api[_-]?secret|authorization|password|token|secret)\s*[:=]\s*")([^"]*)(")/iu
  @single_quoted_assignment ~r/((?:api[_-]?key|api[_-]?secret|authorization|password|token|secret)\s*[:=]\s*')([^']*)(')/iu
  @json_assignment ~r/("(?:(?:api[_-]?key|api[_-]?secret|authorization|password|token|secret|cookie|credential|access[_-]?key|secret[_-]?key))"\s*:\s*")([^"]*)(")/iu
  @single_quoted_json_assignment ~r/('(?:(?:api[_-]?key|api[_-]?secret|authorization|password|token|secret|cookie|credential|access[_-]?key|secret[_-]?key))'\s*:\s*')([^']*)(')/iu
  @provider_token_value ~r/\b(?:sk|ghp|github_pat|xox[baprs]|xapp|xoxc|xoxe|ya29)[-_][A-Za-z0-9._:-]+\b/

  @spec redact(term()) :: term()
  def redact(value), do: do_redact(value)

  @spec configure_from_observability(map() | struct() | term()) :: :ok
  def configure_from_observability(observability) do
    :persistent_term.put(
      @summary_bytes_key,
      normalize_summary_max_bytes(fetch_observability_value(observability, :summary_max_bytes))
    )

    :ok
  end

  @spec summary_max_bytes() :: pos_integer()
  def summary_max_bytes do
    :persistent_term.get(@summary_bytes_key, @default_summary_bytes)
  end

  @spec summarize(term()) :: String.t()
  def summarize(value), do: summarize(value, summary_max_bytes())

  @spec summarize(term(), pos_integer()) :: String.t()
  def summarize(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    value
    |> redact()
    |> inspect(limit: 20, printable_limit: max_bytes)
    |> truncate(max_bytes)
  end

  @spec redact_string(String.t()) :: String.t()
  def redact_string(value) when is_binary(value) do
    value
    |> String.replace(@bearer_like_value, fn match ->
      [scheme | _] = String.split(match, ~r/\s+/, parts: 2)
      scheme <> " " <> @redacted
    end)
    |> String.replace(@env_assignment, "\\1=#{@redacted}")
    |> String.replace(@plain_assignment, "\\1#{@redacted}")
    |> String.replace(@quoted_assignment, "\\1#{@redacted}\\3")
    |> String.replace(@single_quoted_assignment, "\\1#{@redacted}\\3")
    |> String.replace(@json_assignment, "\\1#{@redacted}\\3")
    |> String.replace(@single_quoted_json_assignment, "\\1#{@redacted}\\3")
    |> String.replace(@provider_token_value, @redacted)
  end

  defp do_redact(nil), do: nil
  defp do_redact(value) when is_boolean(value) or is_integer(value) or is_float(value), do: value

  defp do_redact(value) when is_binary(value) do
    redact_string(value)
  end

  defp do_redact(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp do_redact(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp do_redact(%Date{} = value), do: Date.to_iso8601(value)
  defp do_redact(%Time{} = value), do: Time.to_iso8601(value)

  defp do_redact(%_{} = value) do
    value
    |> Map.from_struct()
    |> do_redact()
  end

  defp do_redact(value) when is_map(value) do
    Map.new(value, fn {key, map_value} ->
      normalized_key = to_string(key)

      redacted_value =
        if sensitive_key?(normalized_key) do
          @redacted
        else
          do_redact(map_value)
        end

      {normalized_key, redacted_value}
    end)
  end

  defp do_redact(value) when is_list(value) do
    Enum.map(value, &do_redact/1)
  end

  defp do_redact(value) when is_atom(value), do: Atom.to_string(value)
  defp do_redact(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&do_redact/1)
  defp do_redact(value), do: inspect(value)

  defp sensitive_key?(key) when is_binary(key) do
    normalized =
      key
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/u, "")

    token_secret_key?(normalized) or
      Enum.any?(@sensitive_key_fragments, &String.contains?(normalized, &1))
  end

  defp truncate(value, max_bytes) when is_binary(value) and is_integer(max_bytes) and max_bytes > 0 do
    if byte_size(value) > max_bytes do
      valid_binary_prefix(value, max_bytes) <> "...<truncated>"
    else
      value
    end
  end

  defp token_secret_key?("token"), do: true
  defp token_secret_key?("accesstoken"), do: true
  defp token_secret_key?("refreshtoken"), do: true
  defp token_secret_key?("idtoken"), do: true
  defp token_secret_key?("sessiontoken"), do: true
  defp token_secret_key?("authtoken"), do: true
  defp token_secret_key?("bearertoken"), do: true
  defp token_secret_key?(key) when is_binary(key), do: String.ends_with?(key, "token")

  defp valid_binary_prefix(value, byte_count) when byte_count <= 0 or value == "", do: ""

  defp valid_binary_prefix(value, byte_count) when is_binary(value) and is_integer(byte_count) do
    byte_count = min(byte_count, byte_size(value))
    candidate = binary_part(value, 0, byte_count)

    if String.valid?(candidate) do
      candidate
    else
      valid_binary_prefix(value, byte_count - 1)
    end
  end

  defp fetch_observability_value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(map, Atom.to_string(key))
    end
  end

  defp fetch_observability_value(_value, _key), do: nil

  defp normalize_summary_max_bytes(value) when is_integer(value) and value > 0, do: value
  defp normalize_summary_max_bytes(_value), do: @default_summary_bytes
end
