defmodule SymphonyElixir.Observability.LogFile.FileHandler do
  @moduledoc false

  alias SymphonyElixir.Observability.LogFile.{FormatterConfig, PathConfig, SinkEvent}

  @file_handler_id :symphony_disk_log

  @spec ensure(boolean(), Path.t(), integer(), integer(), :json | :text) :: :ok
  def ensure(false, _log_file, _max_bytes, _max_files, _log_format) do
    remove_existing_handler(:disable)
  end

  def ensure(true, log_file, max_bytes, max_files, log_format) do
    expanded_path = PathConfig.expand(log_file)
    log_format_name = FormatterConfig.name(log_format)

    case PathConfig.ensure_parent_directory(expanded_path) do
      :ok ->
        :ok = remove_existing_handler(:refresh)
        add_handler(expanded_path, max_bytes, max_files, log_format, log_format_name)

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :file,
          @file_handler_id,
          "ensure_directory",
          %{
            file_path: expanded_path,
            log_format: log_format_name,
            error: inspect(reason)
          }
        )

        :ok
    end
  end

  defp add_handler(expanded_path, max_bytes, max_files, log_format, log_format_name) do
    case :logger.add_handler(
           @file_handler_id,
           :logger_disk_log_h,
           handler_config(expanded_path, max_bytes, max_files, log_format)
         ) do
      :ok ->
        SinkEvent.emit(
          :info,
          :log_sink_configured,
          :file,
          @file_handler_id,
          "configure",
          %{
            file_path: expanded_path,
            log_format: log_format_name
          }
        )

        :ok

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :file,
          @file_handler_id,
          "configure",
          %{
            file_path: expanded_path,
            log_format: log_format_name,
            error: inspect(reason)
          }
        )

        :ok
    end
  end

  defp remove_existing_handler(context) when context in [:disable, :refresh] do
    case :logger.remove_handler(@file_handler_id) do
      :ok ->
        if context == :disable do
          SinkEvent.emit(
            :info,
            :log_sink_disabled,
            :file,
            @file_handler_id,
            "remove"
          )
        end

        :ok

      {:error, {:not_found, @file_handler_id}} ->
        :ok

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_disable_failed,
          :file,
          @file_handler_id,
          remove_action(context),
          %{error: inspect(reason)}
        )

        :ok
    end
  end

  defp handler_config(path, max_bytes, max_files, log_format) do
    %{
      level: :all,
      formatter: FormatterConfig.for_format(log_format),
      config: %{
        file: String.to_charlist(path),
        type: :wrap,
        max_no_bytes: max_bytes,
        max_no_files: max_files
      }
    }
  end

  defp remove_action(:disable), do: "remove"
  defp remove_action(:refresh), do: "refresh_remove"
end
