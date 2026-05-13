defmodule SymphonyElixir.LogFileTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias SymphonyElixir.Observability.Formatter, as: ObservabilityFormatter
  alias SymphonyElixir.Observability.LogFile

  setup do
    original_handler = :logger.get_handler_config(:symphony_disk_log)
    original_console_handler = :logger.get_handler_config(:default)

    on_exit(fn ->
      restore_handler(:symphony_disk_log, :logger_disk_log_h, original_handler)
      restore_handler(:default, :logger_std_h, original_console_handler)
    end)

    :ok
  end

  test "default_log_file/0 uses the current working directory" do
    assert LogFile.default_log_file() == Path.join(File.cwd!(), "log/symphony.log")
  end

  test "default_log_file/1 builds the log path under a custom root" do
    assert LogFile.default_log_file("/tmp/symphony-logs") == "/tmp/symphony-logs/log/symphony.log"
  end

  test "configure_from_observability keeps the default console handler when console is enabled" do
    log =
      capture_log(fn ->
        assert :ok =
                 LogFile.configure_from_observability(%{
                   file_enabled: true,
                   console_enabled: true,
                   log_format: "text"
                 })
      end)

    assert {:ok, handler_config} = :logger.get_handler_config(:default)
    assert handler_config.module == :logger_std_h
    assert {Logger.Formatter, formatter} = handler_config.formatter
    assert :event in formatter.metadata
    assert :request_id in formatter.metadata
    assert :run_id in formatter.metadata
    assert :issue_id in formatter.metadata
    assert log =~ "log_sink_configured sink_name=console handler_id=default"
    assert log =~ "log_sink_configured sink_name=file handler_id=symphony_disk_log action=configure"
  end

  test "configure_from_observability can disable the rotating file handler" do
    log =
      capture_log(fn ->
        assert :ok =
                 LogFile.configure_from_observability(%{
                   file_enabled: false,
                   console_enabled: true,
                   log_format: "text"
                 })
      end)

    assert {:error, {:not_found, :symphony_disk_log}} = :logger.get_handler_config(:symphony_disk_log)
    assert log =~ "log_sink_disabled sink_name=file handler_id=symphony_disk_log action=remove"
  end

  test "configure_from_observability can switch the rotating file handler to JSON formatting" do
    assert :ok =
             LogFile.configure_from_observability(%{
               file_enabled: true,
               console_enabled: true,
               log_format: "json"
             })

    assert {:ok, handler_config} = :logger.get_handler_config(:symphony_disk_log)
    assert handler_config.module == :logger_disk_log_h
    assert handler_config.formatter == {ObservabilityFormatter, %{}}
  end

  test "configure_from_observability defaults the rotating file handler to JSON formatting" do
    assert :ok =
             LogFile.configure_from_observability(%{
               file_enabled: true,
               console_enabled: true
             })

    assert {:ok, handler_config} = :logger.get_handler_config(:symphony_disk_log)
    assert handler_config.module == :logger_disk_log_h
    assert handler_config.formatter == {ObservabilityFormatter, %{}}
  end

  test "configure_from_observability treats nil log_format as the default JSON format" do
    assert :ok =
             LogFile.configure_from_observability(%{
               file_enabled: true,
               console_enabled: true,
               log_format: nil
             })

    assert {:ok, handler_config} = :logger.get_handler_config(:symphony_disk_log)
    assert handler_config.formatter == {ObservabilityFormatter, %{}}
  end

  test "configure_from_observability emits structured failure events when log directory setup fails" do
    original_log_file = Application.get_env(:symphony_elixir, :log_file)
    blocking_path = Path.join(System.tmp_dir!(), "symphony-log-blocker-#{System.unique_integer([:positive])}")
    invalid_log_path = Path.join(blocking_path, "symphony.log")
    File.write!(blocking_path, "block")

    on_exit(fn ->
      if is_nil(original_log_file) do
        Application.delete_env(:symphony_elixir, :log_file)
      else
        Application.put_env(:symphony_elixir, :log_file, original_log_file)
      end

      File.rm_rf(blocking_path)
    end)

    Application.put_env(:symphony_elixir, :log_file, invalid_log_path)

    log =
      capture_log(fn ->
        assert :ok =
                 LogFile.configure_from_observability(%{
                   file_enabled: true,
                   console_enabled: true,
                   log_format: "json"
                 })
      end)

    assert log =~ "log_sink_configuration_failed sink_name=file handler_id=symphony_disk_log action=ensure_directory"
    assert log =~ invalid_log_path
    assert log =~ "log_format=json"
  end

  defp restore_handler(handler_id, module, {:ok, config}) do
    :ok = remove_handler(handler_id)

    config
    |> Map.drop([:id, :module])
    |> then(fn handler_config ->
      case :logger.add_handler(handler_id, module, handler_config) do
        :ok -> :ok
        {:error, {:already_exists, ^handler_id}} -> :ok
      end
    end)
  end

  defp restore_handler(handler_id, _module, {:error, {:not_found, missing_handler_id}})
       when missing_handler_id == handler_id do
    :ok = remove_handler(handler_id)
  end

  defp remove_handler(handler_id) do
    case :logger.remove_handler(handler_id) do
      :ok -> :ok
      {:error, {:not_found, ^handler_id}} -> :ok
    end
  end
end
