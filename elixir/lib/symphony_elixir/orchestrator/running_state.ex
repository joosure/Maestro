defmodule SymphonyElixir.Orchestrator.RunningState do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Redaction
  alias SymphonyElixir.Orchestrator.AgentUsage

  @empty_token_delta %{
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    input_reported: 0,
    output_reported: 0,
    total_reported: 0
  }

  @spec merge_worker_runtime_info(map(), Runtime.worker_runtime_info()) :: map()
  def merge_worker_runtime_info(running_entry, runtime_info)
      when is_map(running_entry) and is_map(runtime_info) do
    running_entry
    |> maybe_put_runtime_value(:run_id, runtime_info[:run_id])
    |> maybe_put_runtime_value(:agent_provider_kind, runtime_info[:agent_provider_kind])
    |> maybe_put_runtime_value(:agent_process_pid, runtime_info[:agent_process_pid])
    |> maybe_put_runtime_value(:worker_host, runtime_info[:worker_host])
    |> maybe_put_runtime_value(:worker_daemon_endpoint, runtime_info[:worker_daemon_endpoint])
    |> maybe_put_runtime_value(:worker_daemon_endpoint_id, runtime_info[:worker_daemon_endpoint_id])
    |> maybe_put_runtime_value(:worker_daemon_worker_id, runtime_info[:worker_daemon_worker_id])
    |> maybe_put_runtime_value(:worker_daemon_daemon_instance_id, runtime_info[:worker_daemon_daemon_instance_id])
    |> maybe_put_runtime_value(:workspace_path, runtime_info[:workspace_path])
    |> maybe_put_issue_fact(runtime_info)
    |> maybe_put_runtime_value(:failure_class, runtime_info[:failure_class])
    |> maybe_put_runtime_value(:last_error, runtime_info[:error])
  end

  def merge_worker_runtime_info(running_entry, _runtime_info), do: running_entry

  defp maybe_put_issue_fact(running_entry, %{issue: %Issue{} = issue} = runtime_info)
       when is_map(running_entry) do
    running_entry
    |> Map.put(:issue, issue)
    |> Map.put(:issue_fact_updated_at_ms, monotonic_ms(runtime_info))
    |> maybe_put_runtime_value(:issue_fact_source, runtime_info[:issue_fact_source])
  end

  defp maybe_put_issue_fact(running_entry, _runtime_info), do: running_entry

  defp monotonic_ms(%{monotonic_ms: monotonic_ms}) when is_integer(monotonic_ms), do: monotonic_ms
  defp monotonic_ms(_runtime_info), do: System.monotonic_time(:millisecond)

  @spec integrate_agent_update(map(), map()) :: {map(), map()}
  def integrate_agent_update(running_entry, %{event: event, timestamp: timestamp} = update)
      when is_map(running_entry) do
    token_delta = AgentUsage.token_delta(running_entry, update)
    agent_input_tokens = Map.get(running_entry, :agent_input_tokens, 0)
    agent_output_tokens = Map.get(running_entry, :agent_output_tokens, 0)
    agent_total_tokens = Map.get(running_entry, :agent_total_tokens, 0)
    agent_process_pid = Map.get(running_entry, :agent_process_pid)
    agent_last_reported_input = Map.get(running_entry, :agent_last_reported_input_tokens, 0)
    agent_last_reported_output = Map.get(running_entry, :agent_last_reported_output_tokens, 0)
    agent_last_reported_total = Map.get(running_entry, :agent_last_reported_total_tokens, 0)
    turn_count = Map.get(running_entry, :turn_count, 0)
    existing_session_id = Map.get(running_entry, :session_id)
    summarized_update = summarize_agent_update(update)
    process_pid = agent_process_pid_for_update(agent_process_pid, update)

    {
      Map.merge(running_entry, %{
        run_id: update_value(update, :run_id) || Map.get(running_entry, :run_id),
        agent_provider_kind: update_value(update, :agent_provider_kind) || Map.get(running_entry, :agent_provider_kind),
        last_agent_timestamp: timestamp,
        last_agent_message: summarized_update,
        last_agent_event: event,
        agent_process_pid: process_pid,
        agent_input_tokens: agent_input_tokens + token_delta.input_tokens,
        agent_output_tokens: agent_output_tokens + token_delta.output_tokens,
        agent_total_tokens: agent_total_tokens + token_delta.total_tokens,
        agent_last_reported_input_tokens: max(agent_last_reported_input, token_delta.input_reported),
        agent_last_reported_output_tokens: max(agent_last_reported_output, token_delta.output_reported),
        agent_last_reported_total_tokens: max(agent_last_reported_total, token_delta.total_reported),
        session_id: session_id_for_update(existing_session_id, update),
        turn_count: turn_count_for_update(turn_count, existing_session_id, update)
      }),
      token_delta
    }
  end

  def integrate_agent_update(running_entry, _update), do: {running_entry, @empty_token_delta}

  @spec record_session_completion(map(), map()) :: map()
  def record_session_completion(%{agent_totals: agent_totals} = state, running_entry)
      when is_map(running_entry) and is_map(agent_totals) do
    runtime_seconds = AgentUsage.running_seconds(running_entry.started_at, DateTime.utc_now())

    delta = %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      seconds_running: runtime_seconds
    }

    %{
      state
      | agent_totals: AgentUsage.apply_delta(agent_totals, delta)
    }
  end

  def record_session_completion(state, _running_entry), do: state

  @spec apply_token_delta(map(), map()) :: map()
  def apply_token_delta(
        %{agent_totals: agent_totals} = state,
        %{input_tokens: input, output_tokens: output, total_tokens: total} = token_delta
      )
      when is_map(agent_totals) and is_integer(input) and is_integer(output) and is_integer(total) do
    %{
      state
      | agent_totals: AgentUsage.apply_delta(agent_totals, token_delta)
    }
  end

  def apply_token_delta(state, _token_delta), do: state

  @spec apply_rate_limits(map(), map()) :: map()
  def apply_rate_limits(state, update) when is_map(state) and is_map(update) do
    case AgentUsage.extract_rate_limits(update) do
      %{} = rate_limits ->
        %{state | agent_rate_limits: rate_limits}

      _ ->
        state
    end
  end

  def apply_rate_limits(state, _update), do: state

  defp maybe_put_runtime_value(running_entry, _key, nil), do: running_entry

  defp maybe_put_runtime_value(running_entry, key, value) when is_map(running_entry) do
    Map.put(running_entry, key, value)
  end

  defp agent_process_pid_for_update(_existing, %{agent_process_pid: pid}), do: normalize_pid(pid)
  defp agent_process_pid_for_update(_existing, %{provider_process_pid: pid}), do: normalize_pid(pid)
  defp agent_process_pid_for_update(_existing, %{"agent_process_pid" => pid}), do: normalize_pid(pid)
  defp agent_process_pid_for_update(_existing, %{"provider_process_pid" => pid}), do: normalize_pid(pid)
  defp agent_process_pid_for_update(existing, _update), do: existing

  defp normalize_pid(pid) when is_binary(pid), do: pid
  defp normalize_pid(pid) when is_integer(pid), do: Integer.to_string(pid)
  defp normalize_pid(pid) when is_list(pid), do: to_string(pid)
  defp normalize_pid(_pid), do: nil

  defp session_id_for_update(_existing, %{session_id: session_id}) when is_binary(session_id),
    do: session_id

  defp session_id_for_update(_existing, %{"session_id" => session_id}) when is_binary(session_id),
    do: session_id

  defp session_id_for_update(existing, _update), do: existing

  defp turn_count_for_update(existing_count, existing_session_id, %{
         event: :session_started,
         session_id: session_id
       })
       when is_integer(existing_count) and is_binary(session_id) do
    if session_id == existing_session_id do
      existing_count
    else
      existing_count + 1
    end
  end

  defp turn_count_for_update(existing_count, _existing_session_id, _update)
       when is_integer(existing_count),
       do: existing_count

  defp turn_count_for_update(_existing_count, _existing_session_id, _update), do: 0

  defp summarize_agent_update(update) do
    provider_kind = update_value(update, :agent_provider_kind)

    %{
      event: update_value(update, :event),
      message: present_agent_update(update, provider_kind),
      timestamp: update_value(update, :timestamp)
    }
    |> maybe_put_summary_provider_kind(provider_kind)
  end

  defp present_agent_update(update, provider_kind) do
    update
    |> presentable_agent_update(provider_kind)
    |> AgentProvider.present_message(agent_provider_opts(provider_kind))
  rescue
    _error -> summarized_update_message(update)
  end

  defp presentable_agent_update(update, provider_kind) do
    %{
      event: update_value(update, :event),
      message: structured_update_message(update),
      timestamp: update_value(update, :timestamp)
    }
    |> maybe_put_summary_provider_kind(provider_kind)
  end

  defp structured_update_message(update) do
    update
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if key in [:payload, "payload", :result, "result", :reason, "reason", :title, "title", :usage, "usage"] do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
    |> case do
      empty when map_size(empty) == 0 -> update_value(update, :raw) || update
      summary_payload -> summary_payload
    end
  end

  defp maybe_put_summary_provider_kind(summary, provider_kind) when is_binary(provider_kind),
    do: Map.put(summary, :agent_provider_kind, provider_kind)

  defp maybe_put_summary_provider_kind(summary, _provider_kind), do: summary

  defp agent_provider_opts(provider_kind) when is_binary(provider_kind) do
    if AgentProvider.adapter_for(provider_kind), do: [kind: provider_kind], else: []
  end

  defp agent_provider_opts(_provider_kind), do: []

  defp summarized_update_message(update) do
    update_value(update, :payload_summary) ||
      update_value(update, :result_summary) ||
      summarize_if_present(update_value(update, :payload)) ||
      summarize_if_present(update_value(update, :raw))
  end

  defp summarize_if_present(nil), do: nil
  defp summarize_if_present(value), do: Redaction.summarize(value, 256)

  defp update_value(update, key) when is_map(update) and is_atom(key) do
    Map.get(update, key) || Map.get(update, Atom.to_string(key))
  end
end
