defmodule SymphonyElixir.Agent.Continuation do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Tracker.{Config, Error}
  alias SymphonyElixir.Workflow.IssueContext

  @issue_state_refresh_retry_delays_ms [15_000, 45_000, 90_000]

  @spec continue_with_issue(Issue.t(), ([String.t()] -> term()), keyword()) ::
          {:continue, Issue.t()} | {:done, Issue.t()} | {:error, term()}
  def continue_with_issue(%Issue{id: issue_id} = issue, issue_state_fetcher, opts)
      when is_binary(issue_id) and is_function(issue_state_fetcher, 1) and is_list(opts) do
    run_id = Keyword.get(opts, :run_id)

    retry_delays_ms =
      Keyword.get(
        opts,
        :issue_state_refresh_retry_delays_ms,
        @issue_state_refresh_retry_delays_ms
      )

    case fetch_issue_states_with_retry(issue_id, issue_state_fetcher, retry_delays_ms, opts) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if active_issue_state?(refreshed_issue, refreshed_issue.state) do
          {:continue, refreshed_issue}
        else
          {:done, refreshed_issue}
        end

      {:ok, []} ->
        {:done, issue}

      {:error, reason} ->
        emit_issue_state_refresh_failed(issue, reason, run_id)
        {:error, {:issue_state_refresh_failed, reason}}
    end
  end

  def continue_with_issue(issue, _issue_state_fetcher, _opts), do: {:done, issue}

  defp fetch_issue_states_with_retry(issue_id, issue_state_fetcher, retry_delays_ms, opts) do
    do_fetch_issue_states_with_retry(
      issue_id,
      issue_state_fetcher,
      normalize_retry_delays(retry_delays_ms),
      opts
    )
  end

  defp do_fetch_issue_states_with_retry(
         issue_id,
         issue_state_fetcher,
         [delay_ms | remaining_delays],
         opts
       ) do
    case issue_state_fetcher.([issue_id]) do
      {:error, reason} = error ->
        normalized_error = if match?(%Error{}, reason), do: reason, else: nil

        if transient_issue_state_refresh_error?(reason) do
          ObsLogger.emit(
            :warning,
            :issue_state_refresh_retry_scheduled,
            %{
              component: "agent_runner",
              run_id: Keyword.get(opts, :run_id),
              correlation_id: Keyword.get(opts, :run_id),
              issue_id: issue_id,
              tracker_kind: tracker_kind(),
              worker_host: Keyword.get(opts, :worker_host),
              workspace_path: Keyword.get(opts, :workspace),
              duration_ms: delay_ms,
              error: inspect(reason),
              normalized_error: inspect(normalized_error || reason)
            }
          )

          Process.sleep(delay_ms)
          do_fetch_issue_states_with_retry(issue_id, issue_state_fetcher, remaining_delays, opts)
        else
          error
        end

      result ->
        result
    end
  end

  defp do_fetch_issue_states_with_retry(issue_id, issue_state_fetcher, [], _opts) do
    issue_state_fetcher.([issue_id])
  end

  defp emit_issue_state_refresh_failed(%Issue{} = issue, reason, run_id) do
    ObsLogger.emit(
      :error,
      :issue_state_refresh_failed,
      %{
        component: "agent_runner",
        tracker_kind: tracker_kind(),
        issue_id: issue.id,
        issue_identifier: issue.identifier,
        worker_host: nil,
        workspace_path: nil,
        run_id: run_id,
        correlation_id: run_id,
        current_state: issue.state,
        error: inspect(reason),
        result_summary: "issue_state_refresh_failed",
        message: "issue_state_refresh_failed issue_id=#{issue.id} issue_identifier=#{issue.identifier} current_state=#{inspect(issue.state)} error=#{inspect(reason)}"
      }
    )
  end

  defp normalize_retry_delays(delays) when is_list(delays) do
    delays
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
  end

  defp normalize_retry_delays(_delays), do: @issue_state_refresh_retry_delays_ms

  defp transient_issue_state_refresh_error?({
         :tapd_workflow_lookup_failed,
         _workitem_type_id,
         _type,
         reason
       }) do
    transient_issue_state_refresh_error?(reason)
  end

  defp transient_issue_state_refresh_error?(%Error{} = error), do: Error.retryable?(error)

  defp transient_issue_state_refresh_error?({:tapd_http_status, status, _body}),
    do: transient_http_status?(status)

  defp transient_issue_state_refresh_error?({:linear_api_status, status}),
    do: transient_http_status?(status)

  defp transient_issue_state_refresh_error?({:tapd_request, _reason}), do: true
  defp transient_issue_state_refresh_error?({:linear_api_request, _reason}), do: true
  defp transient_issue_state_refresh_error?(_reason), do: false

  defp transient_http_status?(status) when status in [408, 429, 500, 502, 503, 504], do: true
  defp transient_http_status?(_status), do: false

  defp active_issue_state?(%Issue{} = issue, state_name) when is_binary(state_name) do
    normalized_state = normalize_issue_state(state_name)

    issue
    |> IssueContext.active_states(Config.current!() |> Config.active_states())
    |> Enum.any?(fn active_state -> normalize_issue_state(active_state) == normalized_state end)
  end

  defp active_issue_state?(_issue, _state_name), do: false

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp tracker_kind do
    case Config.current!() |> Config.kind() do
      kind when is_binary(kind) -> kind
      _ -> nil
    end
  end
end
