defmodule SymphonyElixir.Observability.DynamicToolMetrics do
  @moduledoc """
  Stable Dynamic Tool metric keys for event-store projections and dashboards.
  """

  alias SymphonyElixir.Observability.AlertContract

  @total_calls "total_calls"
  @typed_calls "typed_calls"
  @raw_calls "raw_calls"
  @fallback_calls "fallback_calls"
  @typed_tool_hits "typed_tool_hits"
  @raw_tool_attempts "raw_tool_attempts"
  @fallback_count "fallback_count"
  @unsupported_tool_count "unsupported_tool_count"
  @provider_capability_unavailable_count "provider_capability_unavailable_count"
  @provider_capability_unavailable "provider_capability_unavailable"
  @operator_status "operator_status"
  @operator_alerts "operator_alerts"
  @typed_hit_rate "typed_hit_rate"
  @failure_reasons "failure_reasons"
  @by_tool "by_tool"
  @succeeded_calls "succeeded_calls"
  @failed_calls "failed_calls"
  @rejected_calls "rejected_calls"
  @provider_capability_total "total"
  @provider_capability_known "known"
  @provider_capability_unknown "unknown"
  @provider_capability_by_capability "by_capability"

  @spec total_calls() :: String.t()
  def total_calls, do: @total_calls

  @spec typed_calls() :: String.t()
  def typed_calls, do: @typed_calls

  @spec raw_calls() :: String.t()
  def raw_calls, do: @raw_calls

  @spec fallback_calls() :: String.t()
  def fallback_calls, do: @fallback_calls

  @spec usage_calls(String.t()) :: String.t()
  def usage_calls(usage_kind) when is_binary(usage_kind), do: usage_kind <> "_calls"

  @spec status_calls(String.t()) :: String.t()
  def status_calls(status) when is_binary(status), do: status <> "_calls"

  @spec typed_tool_hits() :: String.t()
  def typed_tool_hits, do: @typed_tool_hits

  @spec raw_tool_attempts() :: String.t()
  def raw_tool_attempts, do: @raw_tool_attempts

  @spec fallback_count() :: String.t()
  def fallback_count, do: @fallback_count

  @spec unsupported_tool_count() :: String.t()
  def unsupported_tool_count, do: @unsupported_tool_count

  @spec provider_capability_unavailable_count() :: String.t()
  def provider_capability_unavailable_count, do: @provider_capability_unavailable_count

  @spec provider_capability_unavailable() :: String.t()
  def provider_capability_unavailable, do: @provider_capability_unavailable

  @spec operator_status() :: String.t()
  def operator_status, do: @operator_status

  @spec operator_alerts() :: String.t()
  def operator_alerts, do: @operator_alerts

  @spec typed_hit_rate() :: String.t()
  def typed_hit_rate, do: @typed_hit_rate

  @spec failure_reasons() :: String.t()
  def failure_reasons, do: @failure_reasons

  @spec by_tool() :: String.t()
  def by_tool, do: @by_tool

  @spec succeeded_calls() :: String.t()
  def succeeded_calls, do: @succeeded_calls

  @spec failed_calls() :: String.t()
  def failed_calls, do: @failed_calls

  @spec rejected_calls() :: String.t()
  def rejected_calls, do: @rejected_calls

  @spec provider_capability_total() :: String.t()
  def provider_capability_total, do: @provider_capability_total

  @spec provider_capability_known() :: String.t()
  def provider_capability_known, do: @provider_capability_known

  @spec provider_capability_unknown() :: String.t()
  def provider_capability_unknown, do: @provider_capability_unknown

  @spec provider_capability_by_capability() :: String.t()
  def provider_capability_by_capability, do: @provider_capability_by_capability

  @spec initial() :: map()
  def initial do
    %{
      @total_calls => 0,
      @typed_calls => 0,
      @raw_calls => 0,
      @fallback_calls => 0,
      @typed_tool_hits => 0,
      @raw_tool_attempts => 0,
      @fallback_count => 0,
      @unsupported_tool_count => 0,
      @provider_capability_unavailable_count => 0,
      @provider_capability_unavailable => empty_provider_capability_unavailable(),
      @operator_status => AlertContract.healthy(),
      @operator_alerts => [],
      @typed_hit_rate => 0.0,
      @failure_reasons => %{},
      @by_tool => %{}
    }
  end

  @spec tool_bucket() :: map()
  def tool_bucket do
    %{
      @total_calls => 0,
      @typed_calls => 0,
      @raw_calls => 0,
      @fallback_calls => 0,
      @typed_tool_hits => 0,
      @raw_tool_attempts => 0,
      @fallback_count => 0,
      @unsupported_tool_count => 0,
      @provider_capability_unavailable_count => 0,
      @provider_capability_unavailable => empty_provider_capability_unavailable(),
      @succeeded_calls => 0,
      @failed_calls => 0,
      @rejected_calls => 0,
      @failure_reasons => %{}
    }
  end

  @spec empty_provider_capability_unavailable() :: map()
  def empty_provider_capability_unavailable do
    %{
      @provider_capability_total => 0,
      @provider_capability_known => 0,
      @provider_capability_unknown => 0,
      @provider_capability_by_capability => %{}
    }
  end
end
