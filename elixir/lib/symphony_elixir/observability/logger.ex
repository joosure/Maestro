defmodule SymphonyElixir.Observability.Logger do
  @moduledoc """
  Emits canonical observability events through Elixir's logger.
  """

  require Elixir.Logger

  alias SymphonyElixir.Observability.{Event, EventStore, Fields, Redaction}

  @spec emit(atom(), atom() | String.t(), map()) :: map()
  def emit(level, event, fields \\ %{}) when is_map(fields) do
    payload =
      fields
      |> merge_context_fields()
      |> Redaction.redact()
      |> then(&Event.build(level, event, &1))

    maybe_record_event(payload)
    Elixir.Logger.log(level, payload["message"], event_metadata(payload))
    payload
  rescue
    error ->
      Elixir.Logger.warning("observability_emit_failed event=#{inspect(event)} error=#{Exception.message(error)}")

      %{}
  end

  @spec text(atom(), String.t() | iodata(), map()) :: :ok
  def text(level, message, fields \\ %{}) when is_map(fields) do
    metadata =
      fields
      |> merge_context_fields()
      |> Redaction.redact()
      |> text_metadata()

    sanitized_message =
      message
      |> IO.iodata_to_binary()
      |> Redaction.redact_string()

    Elixir.Logger.log(level, sanitized_message, metadata)
  rescue
    error ->
      Elixir.Logger.warning("observability_text_log_failed error=#{Exception.message(error)}")
      :ok
  end

  @spec format_error(term(), list() | nil) :: String.t()
  def format_error(error, stacktrace \\ nil)

  def format_error(error, stacktrace)
      when is_exception(error) and is_list(stacktrace) and stacktrace != [] do
    Exception.format(:error, error, stacktrace)
  end

  def format_error(error, _stacktrace) when is_exception(error) do
    Exception.format_banner(:error, error)
  end

  def format_error({kind, reason}, stacktrace)
      when kind in [:error, :exit, :throw] and is_list(stacktrace) and stacktrace != [] do
    Exception.format(kind, reason, stacktrace)
  end

  def format_error({kind, reason}, _stacktrace) when kind in [:error, :exit, :throw] do
    Exception.format_banner(kind, reason)
  end

  def format_error(error, _stacktrace), do: inspect(error)

  @spec error_details(term(), list() | nil) :: map()
  def error_details(error, stacktrace \\ nil) do
    formatted_error = format_error(error)
    formatted_stack = format_error(error, stacktrace)

    %{
      error: formatted_error,
      error_stack: if(formatted_stack == formatted_error, do: nil, else: formatted_stack)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp event_metadata(payload) when is_map(payload) do
    base_metadata =
      Enum.reduce(Fields.metadata_fields(), [observability_event: payload], fn key, acc ->
        append_metadata_entry(acc, key, payload)
      end)

    Enum.reverse(base_metadata)
  end

  defp text_metadata(fields) when is_map(fields) do
    Enum.reduce(Fields.metadata_fields(), [], fn key, acc ->
      append_metadata_entry(acc, key, fields)
    end)
    |> Enum.reverse()
  end

  defp append_metadata_entry(acc, key, payload) when is_list(acc) and is_map(payload) do
    case fetch_field(payload, key) do
      {:ok, value} when not is_nil(value) -> [{key, value} | acc]
      _ -> acc
    end
  end

  defp merge_context_fields(fields) when is_map(fields) do
    logger_metadata = Elixir.Logger.metadata()

    fields =
      Enum.reduce(Fields.context_metadata_fields(), fields, fn key, acc ->
        if has_field?(acc, key) do
          acc
        else
          case Keyword.fetch(logger_metadata, key) do
            {:ok, value} -> Map.put(acc, key, value)
            :error -> acc
          end
        end
      end)

    case {fetch_field(fields, :correlation_id), fetch_field(fields, :request_id), fetch_field(fields, :run_id)} do
      {{:ok, _correlation_id}, _request_id, _run_id} ->
        fields

      {:error, {:ok, request_id}, _run_id} ->
        Map.put(fields, :correlation_id, request_id)

      {:error, :error, {:ok, run_id}} ->
        Map.put(fields, :correlation_id, run_id)

      _ ->
        fields
    end
  end

  defp has_field?(fields, key) when is_map(fields) do
    Map.has_key?(fields, key) or Map.has_key?(fields, Atom.to_string(key))
  end

  defp fetch_field(fields, key) when is_map(fields) do
    cond do
      Map.has_key?(fields, key) ->
        {:ok, Map.get(fields, key)}

      Map.has_key?(fields, Atom.to_string(key)) ->
        {:ok, Map.get(fields, Atom.to_string(key))}

      true ->
        :error
    end
  end

  defp maybe_record_event(payload) when is_map(payload) do
    EventStore.record(payload)
  rescue
    _error -> :ok
  end
end
