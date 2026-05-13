defmodule SymphonyElixir.Observability.LogFile do
  @moduledoc """
  Configures OTP logger handlers for Symphony runtime logs.

  The rotating file handler is explicit and Symphony-owned. The default console
  handler remains an OTP concern and is only disabled when configuration
  requests it.
  """

  alias SymphonyElixir.Observability.LogFile.{
    ConsoleHandler,
    FileHandler,
    PathConfig,
    RuntimeConfig
  }

  @spec default_log_file() :: Path.t()
  def default_log_file, do: PathConfig.default_log_file()

  @spec default_log_file(Path.t()) :: Path.t()
  def default_log_file(logs_root), do: PathConfig.default_log_file(logs_root)

  @spec configure() :: :ok
  def configure do
    ConsoleHandler.capture_default_config()

    RuntimeConfig.load()
    |> apply_handler_configuration()
  end

  @spec configure_from_observability(map() | struct()) :: :ok
  def configure_from_observability(observability) do
    ConsoleHandler.capture_default_config()

    observability
    |> RuntimeConfig.load_from_observability()
    |> apply_handler_configuration()
  end

  defp apply_handler_configuration(%{
         path: log_file,
         max_bytes: max_bytes,
         max_files: max_files,
         observability: observability
       }) do
    ConsoleHandler.ensure(Map.fetch!(observability, :console_enabled))

    FileHandler.ensure(
      Map.fetch!(observability, :file_enabled),
      log_file,
      max_bytes,
      max_files,
      Map.fetch!(observability, :log_format)
    )

    :ok
  end
end
