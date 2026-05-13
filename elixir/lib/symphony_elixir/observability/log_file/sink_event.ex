defmodule SymphonyElixir.Observability.LogFile.SinkEvent do
  @moduledoc false

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @component "log_file"

  @spec emit(atom(), atom(), atom(), atom(), String.t(), map()) :: map()
  def emit(level, event, sink_name, handler_id, action, extra_fields \\ %{})
      when is_map(extra_fields) do
    log_format = Map.get(extra_fields, :log_format)
    file_path = Map.get(extra_fields, :file_path)
    error = Map.get(extra_fields, :error)

    summary =
      [
        "sink_name=#{sink_name}",
        "handler_id=#{handler_id_to_string(handler_id)}",
        "action=#{action}"
      ]
      |> append_summary_part("log_format", log_format)
      |> append_summary_part("file_path", file_path)
      |> Enum.join(" ")

    message =
      case error do
        nil -> "#{event} #{summary}"
        _ -> "#{event} #{summary} error=#{error}"
      end

    ObservabilityLogger.emit(
      level,
      event,
      extra_fields
      |> Map.put(:component, @component)
      |> Map.put(:sink_name, to_string(sink_name))
      |> Map.put(:handler_id, handler_id_to_string(handler_id))
      |> Map.put(:result_summary, summary)
      |> Map.put(:message, message)
    )
  end

  defp append_summary_part(parts, _key, nil), do: parts
  defp append_summary_part(parts, _key, ""), do: parts
  defp append_summary_part(parts, key, value), do: parts ++ ["#{key}=#{value}"]

  defp handler_id_to_string(handler_id) when is_atom(handler_id), do: Atom.to_string(handler_id)
end
