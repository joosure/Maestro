defmodule SymphonyElixir.Observability.Formatter do
  @moduledoc """
  JSON Lines formatter for OTP logger handlers.

  Structured observability events are emitted through metadata as canonical maps.
  All other logger events are normalized into the same JSON envelope so file logs
  remain machine-readable.
  """

  @behaviour :logger_formatter

  alias SymphonyElixir.Observability.{Event, EventContract, Fields, Redaction}

  @default_time_offset ~c"Z"
  @message_formatter %{template: [:msg], single_line: true}
  @time_formatter %{template: [:time], single_line: true, time_offset: @default_time_offset}

  @spec check_config(map()) :: :ok | {:error, term()}
  def check_config(config) when is_map(config), do: :ok

  @spec format(map(), map()) :: iodata()
  def format(%{meta: meta} = log_event, _config) when is_map(meta) do
    payload =
      case Map.get(meta, EventContract.observability_event_metadata_key()) do
        %{} = event_payload -> Redaction.redact(event_payload)
        _ -> generic_payload(log_event)
      end

    [Jason.encode_to_iodata!(payload), ?\n]
  rescue
    error ->
      error_payload = %{
        EventContract.timestamp_key() => DateTime.utc_now(:millisecond) |> DateTime.to_iso8601(),
        EventContract.level_key() => "warning",
        EventContract.event_key() => EventContract.formatter_failed_event(),
        EventContract.message_key() => EventContract.formatter_failed_message(),
        EventContract.service_key() => EventContract.service_name(),
        EventContract.component_key() => EventContract.formatter_component(),
        EventContract.error_key() => Exception.message(error)
      }

      [Jason.encode_to_iodata!(error_payload), ?\n]
  end

  defp generic_payload(%{level: level, meta: meta} = log_event) when is_map(meta) do
    event_name =
      meta
      |> Map.get(:event, EventContract.log_message_event())
      |> normalize_text()

    component =
      meta
      |> Map.get(:component, EventContract.logger_component())
      |> normalize_text()

    fields =
      meta
      |> select_generic_metadata()
      |> Map.merge(%{
        EventContract.component_key() => component,
        EventContract.message_key() => format_message(log_event)
      })
      |> Redaction.redact()

    level
    |> Event.build(event_name, fields)
    |> Map.put(EventContract.timestamp_key(), format_timestamp(log_event))
  end

  defp select_generic_metadata(meta) when is_map(meta) do
    Enum.reduce(Fields.generic_metadata_fields(), %{}, fn key, acc ->
      case Map.fetch(meta, key) do
        {:ok, value} -> Map.put(acc, Atom.to_string(key), value)
        :error -> acc
      end
    end)
  end

  defp format_message(log_event) when is_map(log_event) do
    log_event
    |> formatted_message()
    |> message_to_binary()
    |> String.trim()
    |> Redaction.redact_string()
  end

  defp formatted_message(log_event) when is_map(log_event) do
    :logger_formatter.format(log_event, @message_formatter)
  rescue
    _error -> fallback_message(log_event)
  catch
    _kind, _reason -> fallback_message(log_event)
  end

  defp fallback_message(%{msg: {:string, message}}), do: message
  defp fallback_message(%{msg: {:report, report}}), do: inspect_message(report)

  defp fallback_message(%{msg: {format, args}}) when is_list(args) do
    :io_lib.format(format, args)
  rescue
    _error -> inspect_message({format, args})
  catch
    _kind, _reason -> inspect_message({format, args})
  end

  defp fallback_message(%{msg: message}), do: inspect_message(message)
  defp fallback_message(message), do: inspect_message(message)

  defp message_to_binary(message) do
    IO.iodata_to_binary(message)
  rescue
    _error -> inspect_message(message)
  catch
    _kind, _reason -> inspect_message(message)
  end

  defp inspect_message(message) do
    message
    |> Redaction.redact()
    |> inspect(limit: 20, printable_limit: 2_000)
  end

  defp format_timestamp(log_event) when is_map(log_event) do
    log_event
    |> :logger_formatter.format(@time_formatter)
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp normalize_text(value) when is_binary(value), do: value
  defp normalize_text(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_text(value), do: to_string(value)
end
