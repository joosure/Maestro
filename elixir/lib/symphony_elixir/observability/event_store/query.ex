defmodule SymphonyElixir.Observability.EventStore.Query do
  @moduledoc false

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Observability.EventBuffer
  alias SymphonyElixir.Observability.EventStore.{Index, State}

  @terminal_tool_events MapSet.new(["tool_call_succeeded", "tool_call_failed", "tool_call_rejected"])
  @known_provider_unavailable_capabilities MapSet.new(["repo.submit_change_proposal_review"])

  @spec recent_events(State.t(), integer()) :: [map()]
  def recent_events(%State{} = state, limit) do
    state.all_events
    |> EventBuffer.to_list()
    |> records_to_payloads(:desc, limit)
  end

  @spec recent_issue_events(State.t(), map(), integer()) :: [map()]
  def recent_issue_events(%State{} = state, context, limit) when is_map(context) do
    state
    |> recent_issue_records(context)
    |> records_to_payloads(:desc, limit)
  end

  @spec agent_session_logs(State.t(), map(), integer()) :: [map()]
  def agent_session_logs(%State{} = state, context, limit) when is_map(context) do
    state
    |> session_log_records(context)
    |> Enum.filter(&agent_session_log_event?(&1.payload))
    |> records_to_payloads(:asc, limit)
  end

  @spec dynamic_tool_usage_metrics(State.t(), map(), integer()) :: map()
  def dynamic_tool_usage_metrics(%State{} = state, context, limit) when is_map(context) do
    state
    |> dynamic_tool_records(context)
    |> records_to_payloads(:asc, limit)
    |> Enum.filter(&terminal_tool_event?/1)
    |> Enum.reduce(empty_dynamic_tool_usage_metrics(), &accumulate_tool_event/2)
    |> finalize_tool_metrics()
  end

  @spec empty_dynamic_tool_usage_metrics() :: map()
  def empty_dynamic_tool_usage_metrics do
    %{
      "total_calls" => 0,
      "typed_calls" => 0,
      "raw_calls" => 0,
      "fallback_calls" => 0,
      "typed_tool_hits" => 0,
      "raw_tool_attempts" => 0,
      "fallback_count" => 0,
      "unsupported_tool_count" => 0,
      "provider_capability_unavailable_count" => 0,
      "provider_capability_unavailable" => empty_provider_capability_unavailable(),
      "operator_status" => "healthy",
      "operator_alerts" => [],
      "typed_hit_rate" => 0.0,
      "failure_reasons" => %{},
      "by_tool" => %{}
    }
  end

  defp recent_issue_records(state, context) do
    []
    |> collect_records(Index.records(state.issue_events, context["issue_id"]))
    |> collect_records(Index.records(state.issue_identifier_events, context["issue_identifier"]))
    |> collect_records(Index.records(state.run_events, context["run_id"]))
    |> collect_records(Index.records(state.session_events, context["session_id"]))
    |> uniq_records()
  end

  defp session_log_records(state, context) do
    []
    |> collect_records(Index.records(state.session_events, context["session_id"]))
    |> collect_records(Index.records(state.run_events, context["run_id"]))
    |> collect_records(Index.records(state.issue_events, context["issue_id"]))
    |> collect_records(Index.records(state.issue_identifier_events, context["issue_identifier"]))
    |> uniq_records()
  end

  defp dynamic_tool_records(state, context) do
    if map_size(context) == 0 do
      EventBuffer.to_list(state.all_events)
    else
      recent_issue_records(state, context)
    end
  end

  defp collect_records(records, additions) when is_list(records) and is_list(additions) do
    records ++ additions
  end

  defp uniq_records(records) when is_list(records) do
    records
    |> Enum.reduce(%{}, fn %{seq: seq} = record, acc -> Map.put(acc, seq, record) end)
    |> Map.values()
  end

  defp records_to_payloads(records, order, limit)
       when order in [:asc, :desc] and is_integer(limit) and limit > 0 do
    sorter =
      case order do
        :asc -> &<=/2
        :desc -> &>=/2
      end

    records
    |> Enum.sort_by(& &1.seq, sorter)
    |> Enum.take(limit)
    |> Enum.map(& &1.payload)
  end

  defp records_to_payloads(records, order, _limit), do: records_to_payloads(records, order, 1)

  defp agent_session_log_event?(payload) when is_map(payload) do
    component = Map.get(payload, "component", "")
    event = Map.get(payload, "event", "")

    agent_lifecycle_event?(event) or
      AgentProvider.session_log_event?(component, event) or
      String.starts_with?(event, "tool_call_")
  end

  defp agent_lifecycle_event?(event) when is_binary(event) do
    Enum.any?(
      [
        "agent_run_",
        "agent_turn_",
        "agent_session_",
        "agent_cleanup_",
        "agent_provider_"
      ],
      &String.starts_with?(event, &1)
    )
  end

  defp agent_lifecycle_event?(_event), do: false

  defp terminal_tool_event?(payload) when is_map(payload) do
    MapSet.member?(@terminal_tool_events, Map.get(payload, "event"))
  end

  defp terminal_tool_event?(_payload), do: false

  defp accumulate_tool_event(event, metrics) when is_map(event) and is_map(metrics) do
    usage_kind = tool_usage_kind(event)
    tool_name = tool_name(event)
    status = tool_status(event)
    failure_reason = Map.get(event, "dynamic_tool_failure_reason")
    provider_capability_unavailable_count = provider_capability_unavailable_count(event, failure_reason)

    provider_capability_unavailable_details =
      provider_capability_unavailable_details(event, provider_capability_unavailable_count)

    metrics
    |> increment("total_calls")
    |> increment("#{usage_kind}_calls")
    |> maybe_increment_typed_tool_hit(usage_kind, status)
    |> maybe_increment_raw_tool_attempt(usage_kind)
    |> maybe_increment_fallback_count(usage_kind)
    |> maybe_increment_unsupported_tool_count(failure_reason)
    |> add("provider_capability_unavailable_count", provider_capability_unavailable_count)
    |> accumulate_provider_capability_unavailable(provider_capability_unavailable_details)
    |> increment_failure_reason(failure_reason)
    |> update_in(
      ["by_tool"],
      &accumulate_tool_bucket(
        &1 || %{},
        tool_name,
        usage_kind,
        status,
        failure_reason,
        provider_capability_unavailable_count,
        provider_capability_unavailable_details
      )
    )
  end

  defp finalize_tool_metrics(metrics) when is_map(metrics) do
    metrics
    |> put_typed_hit_rate()
    |> put_operator_alerts()
  end

  defp put_typed_hit_rate(%{"total_calls" => total, "typed_calls" => typed} = metrics)
       when is_integer(total) and total > 0 and is_integer(typed) do
    Map.put(metrics, "typed_hit_rate", typed / total)
  end

  defp put_typed_hit_rate(metrics), do: metrics

  defp increment(metrics, key), do: Map.update(metrics, key, 1, &(&1 + 1))

  defp add(metrics, _key, count) when not is_integer(count) or count <= 0, do: metrics
  defp add(metrics, key, count), do: Map.update(metrics, key, count, &(&1 + count))

  defp maybe_increment_typed_tool_hit(metrics, "typed", "succeeded"),
    do: increment(metrics, "typed_tool_hits")

  defp maybe_increment_typed_tool_hit(metrics, _usage_kind, _status), do: metrics

  defp maybe_increment_raw_tool_attempt(metrics, "raw"), do: increment(metrics, "raw_tool_attempts")
  defp maybe_increment_raw_tool_attempt(metrics, _usage_kind), do: metrics

  defp maybe_increment_fallback_count(metrics, "fallback"), do: increment(metrics, "fallback_count")
  defp maybe_increment_fallback_count(metrics, _usage_kind), do: metrics

  defp maybe_increment_unsupported_tool_count(metrics, "unsupported_tool"),
    do: increment(metrics, "unsupported_tool_count")

  defp maybe_increment_unsupported_tool_count(metrics, _failure_reason), do: metrics

  defp empty_provider_capability_unavailable do
    %{
      "total" => 0,
      "known" => 0,
      "unknown" => 0,
      "by_capability" => %{}
    }
  end

  defp accumulate_provider_capability_unavailable(metrics, details) when is_list(details) do
    Enum.reduce(details, metrics, &accumulate_provider_capability_unavailable_detail/2)
  end

  defp accumulate_provider_capability_unavailable_detail(detail, metrics) when is_map(detail) do
    update_in(metrics, ["provider_capability_unavailable"], fn summary ->
      summary
      |> ensure_provider_capability_unavailable()
      |> increment_provider_capability_summary(detail)
    end)
  end

  defp accumulate_provider_capability_unavailable_detail(_detail, metrics), do: metrics

  defp ensure_provider_capability_unavailable(summary) when is_map(summary) do
    empty_provider_capability_unavailable()
    |> Map.merge(summary)
    |> Map.update("by_capability", %{}, fn
      capabilities when is_map(capabilities) -> capabilities
      _capabilities -> %{}
    end)
  end

  defp ensure_provider_capability_unavailable(_summary), do: empty_provider_capability_unavailable()

  defp increment_provider_capability_summary(summary, detail) when is_map(summary) and is_map(detail) do
    capability = provider_unavailable_capability(detail)
    known? = known_provider_unavailable_capability?(capability)
    known_key = if known?, do: "known", else: "unknown"

    summary
    |> increment("total")
    |> increment(known_key)
    |> update_in(["by_capability"], fn by_capability ->
      Map.update(
        by_capability || %{},
        capability || "unknown",
        provider_capability_bucket(detail, known?),
        fn bucket ->
          bucket
          |> increment("count")
          |> Map.put("known", known?)
        end
      )
    end)
  end

  defp provider_capability_bucket(detail, known?) when is_map(detail) do
    %{
      "count" => 1,
      "known" => known?,
      "reason" => Map.get(detail, "reason", "provider_capability_not_available"),
      "description" => Map.get(detail, "description")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp provider_unavailable_capability(detail) when is_map(detail) do
    detail
    |> Map.get("workflowCapability")
    |> normalize_non_empty_string()
  end

  defp known_provider_unavailable_capability?(capability) when is_binary(capability),
    do: MapSet.member?(@known_provider_unavailable_capabilities, capability)

  defp known_provider_unavailable_capability?(_capability), do: false

  defp increment_failure_reason(metrics, reason) when is_binary(reason) and reason != "" do
    update_in(metrics, ["failure_reasons"], fn reasons ->
      Map.update(reasons || %{}, reason, 1, &(&1 + 1))
    end)
  end

  defp increment_failure_reason(metrics, _reason), do: metrics

  defp accumulate_tool_bucket(
         by_tool,
         tool_name,
         usage_kind,
         status,
         failure_reason,
         provider_capability_unavailable_count,
         provider_capability_unavailable_details
       ) do
    Map.update(
      by_tool,
      tool_name,
      tool_bucket(
        usage_kind,
        status,
        failure_reason,
        provider_capability_unavailable_count,
        provider_capability_unavailable_details
      ),
      fn bucket ->
        bucket
        |> increment("total_calls")
        |> increment("#{usage_kind}_calls")
        |> increment("#{status}_calls")
        |> maybe_increment_typed_tool_hit(usage_kind, status)
        |> maybe_increment_raw_tool_attempt(usage_kind)
        |> maybe_increment_fallback_count(usage_kind)
        |> maybe_increment_unsupported_tool_count(failure_reason)
        |> add("provider_capability_unavailable_count", provider_capability_unavailable_count)
        |> accumulate_provider_capability_unavailable(provider_capability_unavailable_details)
        |> increment_failure_reason(failure_reason)
      end
    )
  end

  defp tool_bucket(
         usage_kind,
         status,
         failure_reason,
         provider_capability_unavailable_count,
         provider_capability_unavailable_details
       ) do
    %{
      "total_calls" => 0,
      "typed_calls" => 0,
      "raw_calls" => 0,
      "fallback_calls" => 0,
      "typed_tool_hits" => 0,
      "raw_tool_attempts" => 0,
      "fallback_count" => 0,
      "unsupported_tool_count" => 0,
      "provider_capability_unavailable_count" => 0,
      "provider_capability_unavailable" => empty_provider_capability_unavailable(),
      "succeeded_calls" => 0,
      "failed_calls" => 0,
      "rejected_calls" => 0,
      "failure_reasons" => %{}
    }
    |> increment("total_calls")
    |> increment("#{usage_kind}_calls")
    |> increment("#{status}_calls")
    |> maybe_increment_typed_tool_hit(usage_kind, status)
    |> maybe_increment_raw_tool_attempt(usage_kind)
    |> maybe_increment_fallback_count(usage_kind)
    |> maybe_increment_unsupported_tool_count(failure_reason)
    |> add("provider_capability_unavailable_count", provider_capability_unavailable_count)
    |> accumulate_provider_capability_unavailable(provider_capability_unavailable_details)
    |> increment_failure_reason(failure_reason)
  end

  defp provider_capability_unavailable_count(event, "provider_capability_not_available") do
    event
    |> provider_capability_unavailable_count(nil)
    |> max(1)
  end

  defp provider_capability_unavailable_count(event, _failure_reason) do
    max(
      integer_field(event, "dynamic_tool_provider_capability_unavailable_count"),
      event
      |> Map.get("dynamic_tool_provider_capability_unavailable", [])
      |> normalize_provider_capability_details()
      |> length()
    )
  end

  defp provider_capability_unavailable_details(event, provider_capability_unavailable_count) do
    details =
      event
      |> Map.get("dynamic_tool_provider_capability_unavailable", [])
      |> normalize_provider_capability_details()

    missing_count = max(provider_capability_unavailable_count - length(details), 0)

    details ++ List.duplicate(%{"reason" => "provider_capability_not_available"}, missing_count)
  end

  defp normalize_provider_capability_details(details) when is_list(details) do
    details
    |> Enum.map(&normalize_provider_capability_detail/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_provider_capability_details(%{} = detail) do
    detail
    |> normalize_provider_capability_detail()
    |> case do
      nil -> []
      normalized -> [normalized]
    end
  end

  defp normalize_provider_capability_details(_details), do: []

  defp normalize_provider_capability_detail(%{} = detail) do
    %{
      "workflowCapability" => detail |> Map.get("workflowCapability") |> normalize_non_empty_string(),
      "description" => detail |> Map.get("description") |> normalize_non_empty_string(),
      "reason" =>
        detail
        |> Map.get("reason")
        |> normalize_non_empty_string()
        |> case do
          nil -> "provider_capability_not_available"
          reason -> reason
        end
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_provider_capability_detail(_detail), do: nil

  defp put_operator_alerts(metrics) when is_map(metrics) do
    alerts = operator_alerts(metrics)
    status = operator_status(alerts)

    metrics
    |> Map.put("operator_status", status)
    |> Map.put("operator_alerts", alerts)
  end

  defp operator_alerts(metrics) when is_map(metrics) do
    []
    |> maybe_add_count_alert(
      metrics,
      "raw_tool_attempts",
      "raw_tool_attempts",
      "critical",
      "regression",
      "Normal workflow sessions must not attempt raw or non-planned tools."
    )
    |> maybe_add_count_alert(
      metrics,
      "fallback_count",
      "operator_migration_fallback",
      "warning",
      "operator_migration",
      "Fallback calls are only valid during an explicit operator migration."
    )
    |> maybe_add_count_alert(
      metrics,
      "unsupported_tool_count",
      "unsupported_tool_calls",
      "critical",
      "tool_surface_regression",
      "Unsupported tool calls indicate an agent/tool-surface regression."
    )
    |> maybe_add_provider_unavailable_alerts(metrics)
    |> Enum.reverse()
  end

  defp maybe_add_count_alert(alerts, metrics, metric_key, code, severity, category, message) do
    case Map.get(metrics, metric_key, 0) do
      count when is_integer(count) and count > 0 ->
        [
          %{
            "code" => code,
            "severity" => severity,
            "category" => category,
            "metric" => metric_key,
            "count" => count,
            "message" => message
          }
          | alerts
        ]

      _count ->
        alerts
    end
  end

  defp maybe_add_provider_unavailable_alerts(alerts, metrics) do
    summary = Map.get(metrics, "provider_capability_unavailable", %{})

    alerts
    |> maybe_add_provider_unavailable_alert(
      summary,
      "unknown",
      "provider_capability_unavailable_unknown",
      "warning",
      "provider_capability",
      "Provider capability unavailable reports without a known capability require operator review."
    )
    |> maybe_add_provider_unavailable_alert(
      summary,
      "known",
      "provider_capability_unavailable_known",
      "info",
      "provider_capability",
      "Known provider capability unavailable reports are informational and should not be treated as workflow failures."
    )
  end

  defp maybe_add_provider_unavailable_alert(alerts, summary, count_key, code, severity, category, message) do
    case Map.get(summary, count_key, 0) do
      count when is_integer(count) and count > 0 ->
        [
          %{
            "code" => code,
            "severity" => severity,
            "category" => category,
            "metric" => "provider_capability_unavailable_count",
            "count" => count,
            "capabilities" => provider_unavailable_capabilities(summary, count_key),
            "message" => message
          }
          | alerts
        ]

      _count ->
        alerts
    end
  end

  defp provider_unavailable_capabilities(summary, count_key) when is_map(summary) do
    summary
    |> Map.get("by_capability", %{})
    |> Enum.filter(fn
      {_capability, %{"known" => true}} when count_key == "known" -> true
      {_capability, %{"known" => false}} when count_key == "unknown" -> true
      {_capability, bucket} when count_key == "unknown" and is_map(bucket) -> not Map.get(bucket, "known", false)
      _entry -> false
    end)
    |> Enum.map(fn {capability, _bucket} -> capability end)
    |> Enum.sort()
  end

  defp operator_status([]), do: "healthy"

  defp operator_status(alerts) when is_list(alerts) do
    cond do
      Enum.any?(alerts, &(Map.get(&1, "severity") == "critical")) -> "critical"
      Enum.any?(alerts, &(Map.get(&1, "severity") == "warning")) -> "warning"
      Enum.any?(alerts, &(Map.get(&1, "severity") == "info")) -> "info"
      true -> "healthy"
    end
  end

  defp integer_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_integer(value) and value >= 0 -> value
      value when is_binary(value) -> parse_non_negative_integer(value)
      _value -> 0
    end
  end

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _result -> 0
    end
  end

  defp normalize_non_empty_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_non_empty_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_non_empty_string()
  defp normalize_non_empty_string(_value), do: nil

  defp tool_usage_kind(%{"dynamic_tool_usage_kind" => kind}) when kind in ["typed", "raw", "fallback"], do: kind
  defp tool_usage_kind(_event), do: "raw"

  defp tool_name(%{"tool_name" => tool}) when is_binary(tool) and tool != "", do: tool
  defp tool_name(_event), do: "unknown"

  defp tool_status(%{"event" => "tool_call_succeeded"}), do: "succeeded"
  defp tool_status(%{"event" => "tool_call_failed"}), do: "failed"
  defp tool_status(%{"event" => "tool_call_rejected"}), do: "rejected"
  defp tool_status(_event), do: "failed"
end
