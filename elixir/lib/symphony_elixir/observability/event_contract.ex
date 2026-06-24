defmodule SymphonyElixir.Observability.EventContract do
  @moduledoc """
  Stable observability event envelope keys and default values.

  Observability events are emitted as JSON-compatible, string-keyed maps. This
  contract keeps schema keys centralized while callers can still use atom keys at
  the logging boundary.
  """

  @timestamp_key "timestamp"
  @level_key "level"
  @event_key "event"
  @message_key "message"
  @service_key "service"
  @component_key "component"
  @result_summary_key "result_summary"
  @payload_summary_key "payload_summary"
  @error_key "error"

  @observability_event_metadata_key :observability_event

  @service_name "symphony_elixir"
  @unknown_event "unknown"
  @unknown_component "unknown"
  @logger_component "logger"
  @formatter_component "observability.formatter"
  @log_message_event "log_message"
  @formatter_failed_event "formatter_failed"
  @formatter_failed_message "observability_formatter_failed"

  @spec timestamp_key() :: String.t()
  def timestamp_key, do: @timestamp_key

  @spec level_key() :: String.t()
  def level_key, do: @level_key

  @spec event_key() :: String.t()
  def event_key, do: @event_key

  @spec message_key() :: String.t()
  def message_key, do: @message_key

  @spec service_key() :: String.t()
  def service_key, do: @service_key

  @spec component_key() :: String.t()
  def component_key, do: @component_key

  @spec result_summary_key() :: String.t()
  def result_summary_key, do: @result_summary_key

  @spec payload_summary_key() :: String.t()
  def payload_summary_key, do: @payload_summary_key

  @spec error_key() :: String.t()
  def error_key, do: @error_key

  @spec observability_event_metadata_key() :: atom()
  def observability_event_metadata_key, do: @observability_event_metadata_key

  @spec service_name() :: String.t()
  def service_name, do: @service_name

  @spec unknown_event() :: String.t()
  def unknown_event, do: @unknown_event

  @spec unknown_component() :: String.t()
  def unknown_component, do: @unknown_component

  @spec logger_component() :: String.t()
  def logger_component, do: @logger_component

  @spec formatter_component() :: String.t()
  def formatter_component, do: @formatter_component

  @spec log_message_event() :: String.t()
  def log_message_event, do: @log_message_event

  @spec formatter_failed_event() :: String.t()
  def formatter_failed_event, do: @formatter_failed_event

  @spec formatter_failed_message() :: String.t()
  def formatter_failed_message, do: @formatter_failed_message
end
