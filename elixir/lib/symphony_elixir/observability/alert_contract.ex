defmodule SymphonyElixir.Observability.AlertContract do
  @moduledoc """
  Stable alert envelope keys and severity values for observability projections.
  """

  @code_key "code"
  @severity_key "severity"
  @category_key "category"
  @metric_key "metric"
  @count_key "count"
  @capabilities_key "capabilities"
  @message_key "message"

  @critical "critical"
  @warning "warning"
  @info "info"
  @healthy "healthy"

  @default_category "dynamic_tool"
  @default_message "Dynamic tool alert"

  @spec code_key() :: String.t()
  def code_key, do: @code_key

  @spec severity_key() :: String.t()
  def severity_key, do: @severity_key

  @spec category_key() :: String.t()
  def category_key, do: @category_key

  @spec metric_key() :: String.t()
  def metric_key, do: @metric_key

  @spec count_key() :: String.t()
  def count_key, do: @count_key

  @spec capabilities_key() :: String.t()
  def capabilities_key, do: @capabilities_key

  @spec message_key() :: String.t()
  def message_key, do: @message_key

  @spec critical() :: String.t()
  def critical, do: @critical

  @spec warning() :: String.t()
  def warning, do: @warning

  @spec info() :: String.t()
  def info, do: @info

  @spec healthy() :: String.t()
  def healthy, do: @healthy

  @spec default_category() :: String.t()
  def default_category, do: @default_category

  @spec default_message() :: String.t()
  def default_message, do: @default_message

  @spec count_alert(String.t(), String.t(), String.t(), String.t(), non_neg_integer(), String.t()) ::
          map()
  def count_alert(metric, code, severity, category, count, message)
      when is_binary(metric) and is_binary(code) and is_binary(category) and is_integer(count) and
             count >= 0 and is_binary(message) do
    %{
      @code_key => code,
      @severity_key => normalize_severity(severity),
      @category_key => category,
      @metric_key => metric,
      @count_key => count,
      @message_key => message
    }
  end

  @spec severity(map()) :: String.t()
  def severity(alert) when is_map(alert),
    do: alert |> Map.get(@severity_key) |> normalize_severity()

  @spec capabilities(map()) :: [String.t()]
  def capabilities(%{@capabilities_key => capabilities}) when is_list(capabilities) do
    capabilities
    |> Enum.filter(&is_binary/1)
    |> Enum.sort()
  end

  def capabilities(_alert), do: []

  @spec rollup_status([map()]) :: String.t()
  def rollup_status([]), do: @healthy

  def rollup_status(alerts) when is_list(alerts) do
    cond do
      Enum.any?(alerts, &(severity(&1) == @critical)) -> @critical
      Enum.any?(alerts, &(severity(&1) == @warning)) -> @warning
      Enum.any?(alerts, &(severity(&1) == @info)) -> @info
      true -> @healthy
    end
  end

  @spec normalize_severity(term()) :: String.t()
  def normalize_severity(@critical), do: @critical
  def normalize_severity(@warning), do: @warning
  def normalize_severity(@info), do: @info
  def normalize_severity(_severity), do: @info
end
