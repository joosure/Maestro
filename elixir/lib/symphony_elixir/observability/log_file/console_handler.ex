defmodule SymphonyElixir.Observability.LogFile.ConsoleHandler do
  @moduledoc false

  alias SymphonyElixir.Observability.LogFile.SinkEvent

  @default_console_handler_id :default
  @default_console_handler_key {Module.concat(["SymphonyElixir", "Observability", "LogFile"]), :default_console_handler_config}
  @console_metadata [
    :event,
    :component,
    :request_id,
    :correlation_id,
    :run_id,
    :issue_id,
    :issue_identifier,
    :session_id,
    :thread_id,
    :turn_id,
    :tracker_kind,
    :worker_host,
    :workspace_path,
    :failure_class
  ]

  @spec capture_default_config() :: :ok
  def capture_default_config do
    case :persistent_term.get(@default_console_handler_key, :unset) do
      :unset ->
        capture_default_handler_config()

      _config ->
        :ok
    end
  end

  @spec ensure(boolean()) :: :ok
  def ensure(true) do
    case :logger.get_handler_config(@default_console_handler_id) do
      {:ok, config} ->
        update_handler_config(config)

      {:error, {:not_found, @default_console_handler_id}} ->
        restore_default_handler()

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :console,
          @default_console_handler_id,
          "inspect",
          %{error: inspect(reason)}
        )

        :ok
    end
  end

  def ensure(false) do
    case :logger.remove_handler(@default_console_handler_id) do
      :ok ->
        SinkEvent.emit(
          :info,
          :log_sink_disabled,
          :console,
          @default_console_handler_id,
          "remove"
        )

        :ok

      {:error, {:not_found, @default_console_handler_id}} ->
        :ok

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_disable_failed,
          :console,
          @default_console_handler_id,
          "remove",
          %{error: inspect(reason)}
        )

        :ok
    end
  end

  defp capture_default_handler_config do
    case :logger.get_handler_config(@default_console_handler_id) do
      {:ok, config} ->
        config
        |> enrich_handler_config()
        |> strip_handler_identity()
        |> then(&:persistent_term.put(@default_console_handler_key, &1))

      {:error, {:not_found, @default_console_handler_id}} ->
        :ok

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :console,
          @default_console_handler_id,
          "capture_default_config",
          %{error: inspect(reason)}
        )
    end
  end

  defp restore_default_handler do
    case default_handler_config() do
      nil ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :console,
          @default_console_handler_id,
          "restore_default",
          %{error: "default_console_handler_config_unavailable"}
        )

        :ok

      config ->
        case :logger.add_handler(@default_console_handler_id, :logger_std_h, config) do
          :ok ->
            SinkEvent.emit(
              :info,
              :log_sink_configured,
              :console,
              @default_console_handler_id,
              "restore_default"
            )

            :ok

          {:error, reason} ->
            SinkEvent.emit(
              :warning,
              :log_sink_configuration_failed,
              :console,
              @default_console_handler_id,
              "restore_default",
              %{error: inspect(reason)}
            )

            :ok
        end
    end
  end

  defp default_handler_config do
    case :persistent_term.get(@default_console_handler_key, :unset) do
      :unset -> nil
      config -> config
    end
  end

  defp update_handler_config(config) when is_map(config) do
    updated_config =
      config
      |> enrich_handler_config()
      |> strip_handler_identity()

    case :logger.update_handler_config(@default_console_handler_id, updated_config) do
      :ok ->
        SinkEvent.emit(
          :info,
          :log_sink_configured,
          :console,
          @default_console_handler_id,
          "update"
        )

        :ok

      {:error, reason} ->
        SinkEvent.emit(
          :warning,
          :log_sink_configuration_failed,
          :console,
          @default_console_handler_id,
          "update",
          %{error: inspect(reason)}
        )

        :ok
    end
  end

  defp strip_handler_identity(config) when is_map(config) do
    Map.drop(config, [:id, :module])
  end

  defp enrich_handler_config(%{formatter: formatter} = config) do
    %{config | formatter: enrich_formatter(formatter)}
  end

  defp enrich_handler_config(config), do: config

  defp enrich_formatter({Logger.Formatter, %Logger.Formatter{} = formatter}) do
    metadata =
      formatter.metadata
      |> List.wrap()
      |> Kernel.++(@console_metadata)
      |> Enum.uniq()

    {Logger.Formatter, %{formatter | metadata: metadata}}
  end

  defp enrich_formatter({Logger.Formatter, formatter}) when is_map(formatter) do
    metadata =
      formatter
      |> Map.get(:metadata, [])
      |> List.wrap()
      |> Kernel.++(@console_metadata)
      |> Enum.uniq()

    {Logger.Formatter, Map.put(formatter, :metadata, metadata)}
  end

  defp enrich_formatter(formatter), do: formatter
end
