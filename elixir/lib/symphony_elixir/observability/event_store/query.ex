defmodule SymphonyElixir.Observability.EventStore.Query do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{EventContract, Metadata}
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Capability.Registry, as: CapabilityRegistry
  alias SymphonyElixir.Observability.{AlertContract, DynamicToolAlertContract, DynamicToolMetrics}
  alias SymphonyElixir.Observability.EventContract, as: ObservabilityEventContract
  alias SymphonyElixir.Observability.EventStore.{Buffer, Index, State}

  @terminal_tool_events MapSet.new(EventContract.terminal_event_names())
  @total_calls_key DynamicToolMetrics.total_calls()
  @typed_tool_hits_key DynamicToolMetrics.typed_tool_hits()
  @raw_tool_attempts_key DynamicToolMetrics.raw_tool_attempts()
  @unsupported_tool_count_key DynamicToolMetrics.unsupported_tool_count()
  @provider_capability_unavailable_count_key DynamicToolMetrics.provider_capability_unavailable_count()
  @provider_capability_unavailable_key DynamicToolMetrics.provider_capability_unavailable()
  @operator_status_key DynamicToolMetrics.operator_status()
  @operator_alerts_key DynamicToolMetrics.operator_alerts()
  @typed_hit_rate_key DynamicToolMetrics.typed_hit_rate()
  @failure_reasons_key DynamicToolMetrics.failure_reasons()
  @by_tool_key DynamicToolMetrics.by_tool()
  @typed_calls_key DynamicToolMetrics.typed_calls()
  @provider_capability_total_key DynamicToolMetrics.provider_capability_total()
  @provider_capability_known_key DynamicToolMetrics.provider_capability_known()
  @provider_capability_unknown_key DynamicToolMetrics.provider_capability_unknown()
  @provider_capability_by_capability_key DynamicToolMetrics.provider_capability_by_capability()
  @typed_usage_kind Metadata.Contract.typed_usage_kind()
  @raw_usage_kind Metadata.Contract.raw_usage_kind()
  @tool_status_succeeded EventContract.status_succeeded()
  @unsupported_tool_reason EventContract.unsupported_tool()
  @unknown_tool EventContract.unknown_tool()
  @provider_capability_unavailable_reason Metadata.Contract.provider_capability_unavailable_reason()
  @capability_key Metadata.Contract.capability()
  @description_key Metadata.Contract.description()
  @reason_key Metadata.Contract.reason()
  @alert_count_key AlertContract.count_key()
  @alert_capabilities_key AlertContract.capabilities_key()
  @critical_alert_severity AlertContract.critical()
  @warning_alert_severity AlertContract.warning()
  @info_alert_severity AlertContract.info()
  @raw_tool_attempts_alert_code DynamicToolAlertContract.raw_tool_attempts_code()
  @unsupported_tool_calls_alert_code DynamicToolAlertContract.unsupported_tool_calls_code()
  @provider_capability_unavailable_unknown_alert_code DynamicToolAlertContract.provider_capability_unavailable_unknown_code()
  @provider_capability_unavailable_known_alert_code DynamicToolAlertContract.provider_capability_unavailable_known_code()
  @regression_alert_category DynamicToolAlertContract.regression_category()
  @tool_surface_regression_alert_category DynamicToolAlertContract.tool_surface_regression_category()
  @provider_capability_alert_category DynamicToolAlertContract.provider_capability_category()
  @raw_tool_attempts_alert_message DynamicToolAlertContract.raw_tool_attempts_message()
  @unsupported_tool_calls_alert_message DynamicToolAlertContract.unsupported_tool_calls_message()
  @provider_capability_unavailable_unknown_alert_message DynamicToolAlertContract.provider_capability_unavailable_unknown_message()
  @provider_capability_unavailable_known_alert_message DynamicToolAlertContract.provider_capability_unavailable_known_message()

  @spec recent_events(State.t(), integer()) :: [map()]
  def recent_events(%State{} = state, limit) do
    state.all_events
    |> Buffer.to_list()
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
    DynamicToolMetrics.initial()
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
      Buffer.to_list(state.all_events)
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
    component = Map.get(payload, ObservabilityEventContract.component_key(), ObservabilityEventContract.unknown_component())
    event = Map.get(payload, ObservabilityEventContract.event_key(), ObservabilityEventContract.unknown_event())

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
    MapSet.member?(@terminal_tool_events, Map.get(payload, ObservabilityEventContract.event_key()))
  end

  defp terminal_tool_event?(_payload), do: false

  defp accumulate_tool_event(event, metrics) when is_map(event) and is_map(metrics) do
    usage_kind = tool_usage_kind(event)
    tool_name = tool_name(event)
    status = tool_status(event)
    failure_reason = Map.get(event, "dynamic_tool_failure_reason")

    provider_capability_unavailable_count =
      provider_capability_unavailable_count(event, failure_reason)

    provider_capability_unavailable_details =
      provider_capability_unavailable_details(event, provider_capability_unavailable_count)

    metrics
    |> increment(@total_calls_key)
    |> increment(DynamicToolMetrics.usage_calls(usage_kind))
    |> maybe_increment_typed_tool_hit(usage_kind, status)
    |> maybe_increment_raw_tool_attempt(usage_kind)
    |> maybe_increment_unsupported_tool_count(failure_reason)
    |> add(@provider_capability_unavailable_count_key, provider_capability_unavailable_count)
    |> accumulate_provider_capability_unavailable(provider_capability_unavailable_details)
    |> increment_failure_reason(failure_reason)
    |> update_in(
      [@by_tool_key],
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

  defp put_typed_hit_rate(%{@total_calls_key => total, @typed_calls_key => typed} = metrics)
       when is_integer(total) and total > 0 and is_integer(typed) do
    Map.put(metrics, @typed_hit_rate_key, typed / total)
  end

  defp put_typed_hit_rate(metrics), do: metrics

  defp increment(metrics, key), do: Map.update(metrics, key, 1, &(&1 + 1))

  defp add(metrics, _key, count) when not is_integer(count) or count <= 0, do: metrics
  defp add(metrics, key, count), do: Map.update(metrics, key, count, &(&1 + count))

  defp maybe_increment_typed_tool_hit(metrics, @typed_usage_kind, @tool_status_succeeded),
    do: increment(metrics, @typed_tool_hits_key)

  defp maybe_increment_typed_tool_hit(metrics, _usage_kind, _status), do: metrics

  defp maybe_increment_raw_tool_attempt(metrics, @raw_usage_kind),
    do: increment(metrics, @raw_tool_attempts_key)

  defp maybe_increment_raw_tool_attempt(metrics, _usage_kind), do: metrics

  defp maybe_increment_unsupported_tool_count(metrics, @unsupported_tool_reason),
    do: increment(metrics, @unsupported_tool_count_key)

  defp maybe_increment_unsupported_tool_count(metrics, _failure_reason), do: metrics

  defp empty_provider_capability_unavailable do
    DynamicToolMetrics.empty_provider_capability_unavailable()
  end

  defp accumulate_provider_capability_unavailable(metrics, details) when is_list(details) do
    Enum.reduce(details, metrics, &accumulate_provider_capability_unavailable_detail/2)
  end

  defp accumulate_provider_capability_unavailable_detail(detail, metrics) when is_map(detail) do
    update_in(metrics, [@provider_capability_unavailable_key], fn summary ->
      summary
      |> ensure_provider_capability_unavailable()
      |> increment_provider_capability_summary(detail)
    end)
  end

  defp accumulate_provider_capability_unavailable_detail(_detail, metrics), do: metrics

  defp ensure_provider_capability_unavailable(summary) when is_map(summary) do
    empty_provider_capability_unavailable()
    |> Map.merge(summary)
    |> Map.update(@provider_capability_by_capability_key, %{}, fn
      capabilities when is_map(capabilities) -> capabilities
      _capabilities -> %{}
    end)
  end

  defp ensure_provider_capability_unavailable(_summary),
    do: empty_provider_capability_unavailable()

  defp increment_provider_capability_summary(summary, detail)
       when is_map(summary) and is_map(detail) do
    capability = provider_unavailable_capability(detail)
    known? = known_provider_unavailable_capability?(capability)

    known_key =
      if known?, do: @provider_capability_known_key, else: @provider_capability_unknown_key

    summary
    |> increment(@provider_capability_total_key)
    |> increment(known_key)
    |> update_in([@provider_capability_by_capability_key], fn by_capability ->
      Map.update(
        by_capability || %{},
        capability || @provider_capability_unknown_key,
        provider_capability_bucket(detail, known?),
        fn bucket ->
          bucket
          |> increment(@alert_count_key)
          |> Map.put(@provider_capability_known_key, known?)
        end
      )
    end)
  end

  defp provider_capability_bucket(detail, known?) when is_map(detail) do
    %{
      @alert_count_key => 1,
      @provider_capability_known_key => known?,
      @reason_key => Map.get(detail, @reason_key, @provider_capability_unavailable_reason),
      @description_key => Map.get(detail, @description_key)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp provider_unavailable_capability(detail) when is_map(detail) do
    detail
    |> Map.get(@capability_key)
    |> normalize_non_empty_string()
  end

  defp known_provider_unavailable_capability?(capability) when is_binary(capability),
    do: CapabilityRegistry.known_provider_unavailable_capability?(capability)

  defp known_provider_unavailable_capability?(_capability), do: false

  defp increment_failure_reason(metrics, reason) when is_binary(reason) and reason != "" do
    update_in(metrics, [@failure_reasons_key], fn reasons ->
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
        |> increment(@total_calls_key)
        |> increment(DynamicToolMetrics.usage_calls(usage_kind))
        |> increment(DynamicToolMetrics.status_calls(status))
        |> maybe_increment_typed_tool_hit(usage_kind, status)
        |> maybe_increment_raw_tool_attempt(usage_kind)
        |> maybe_increment_unsupported_tool_count(failure_reason)
        |> add(@provider_capability_unavailable_count_key, provider_capability_unavailable_count)
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
    DynamicToolMetrics.tool_bucket()
    |> increment(@total_calls_key)
    |> increment(DynamicToolMetrics.usage_calls(usage_kind))
    |> increment(DynamicToolMetrics.status_calls(status))
    |> maybe_increment_typed_tool_hit(usage_kind, status)
    |> maybe_increment_raw_tool_attempt(usage_kind)
    |> maybe_increment_unsupported_tool_count(failure_reason)
    |> add(@provider_capability_unavailable_count_key, provider_capability_unavailable_count)
    |> accumulate_provider_capability_unavailable(provider_capability_unavailable_details)
    |> increment_failure_reason(failure_reason)
  end

  defp provider_capability_unavailable_count(event, @provider_capability_unavailable_reason) do
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

    details ++
      List.duplicate(%{@reason_key => @provider_capability_unavailable_reason}, missing_count)
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
      @capability_key => detail |> Map.get(@capability_key) |> normalize_non_empty_string(),
      @description_key => detail |> Map.get(@description_key) |> normalize_non_empty_string(),
      @reason_key =>
        detail
        |> Map.get(@reason_key)
        |> normalize_non_empty_string()
        |> case do
          nil -> @provider_capability_unavailable_reason
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
    |> Map.put(@operator_status_key, status)
    |> Map.put(@operator_alerts_key, alerts)
  end

  defp operator_alerts(metrics) when is_map(metrics) do
    []
    |> maybe_add_count_alert(
      metrics,
      @raw_tool_attempts_key,
      @raw_tool_attempts_alert_code,
      @critical_alert_severity,
      @regression_alert_category,
      @raw_tool_attempts_alert_message
    )
    |> maybe_add_count_alert(
      metrics,
      @unsupported_tool_count_key,
      @unsupported_tool_calls_alert_code,
      @critical_alert_severity,
      @tool_surface_regression_alert_category,
      @unsupported_tool_calls_alert_message
    )
    |> maybe_add_provider_unavailable_alerts(metrics)
    |> Enum.reverse()
  end

  defp maybe_add_count_alert(alerts, metrics, metric_key, code, severity, category, message) do
    case Map.get(metrics, metric_key, 0) do
      count when is_integer(count) and count > 0 ->
        [
          AlertContract.count_alert(metric_key, code, severity, category, count, message)
          | alerts
        ]

      _count ->
        alerts
    end
  end

  defp maybe_add_provider_unavailable_alerts(alerts, metrics) do
    summary = Map.get(metrics, @provider_capability_unavailable_key, %{})

    alerts
    |> maybe_add_provider_unavailable_alert(
      summary,
      @provider_capability_unknown_key,
      @provider_capability_unavailable_unknown_alert_code,
      @warning_alert_severity,
      @provider_capability_alert_category,
      @provider_capability_unavailable_unknown_alert_message
    )
    |> maybe_add_provider_unavailable_alert(
      summary,
      @provider_capability_known_key,
      @provider_capability_unavailable_known_alert_code,
      @info_alert_severity,
      @provider_capability_alert_category,
      @provider_capability_unavailable_known_alert_message
    )
  end

  defp maybe_add_provider_unavailable_alert(
         alerts,
         summary,
         count_key,
         code,
         severity,
         category,
         message
       ) do
    case Map.get(summary, count_key, 0) do
      count when is_integer(count) and count > 0 ->
        [
          @provider_capability_unavailable_count_key
          |> AlertContract.count_alert(code, severity, category, count, message)
          |> Map.put(
            @alert_capabilities_key,
            provider_unavailable_capabilities(summary, count_key)
          )
          | alerts
        ]

      _count ->
        alerts
    end
  end

  defp provider_unavailable_capabilities(summary, count_key) when is_map(summary) do
    summary
    |> Map.get(@provider_capability_by_capability_key, %{})
    |> Enum.filter(fn
      {_capability, %{@provider_capability_known_key => true}}
      when count_key == @provider_capability_known_key ->
        true

      {_capability, %{@provider_capability_known_key => false}}
      when count_key == @provider_capability_unknown_key ->
        true

      {_capability, bucket}
      when count_key == @provider_capability_unknown_key and is_map(bucket) ->
        not Map.get(bucket, @provider_capability_known_key, false)

      _entry ->
        false
    end)
    |> Enum.map(fn {capability, _bucket} -> capability end)
    |> Enum.sort()
  end

  defp operator_status(alerts) when is_list(alerts), do: AlertContract.rollup_status(alerts)

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

  defp normalize_non_empty_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_non_empty_string()

  defp normalize_non_empty_string(_value), do: nil

  defp tool_usage_kind(%{"dynamic_tool_usage_kind" => kind})
       when kind in [@typed_usage_kind, @raw_usage_kind], do: kind

  defp tool_usage_kind(_event), do: @raw_usage_kind

  defp tool_name(%{"tool_name" => tool}) when is_binary(tool) and tool != "", do: tool
  defp tool_name(_event), do: @unknown_tool

  defp tool_status(event) when is_map(event),
    do: event |> Map.get(ObservabilityEventContract.event_key()) |> EventContract.status_for_event()
end
