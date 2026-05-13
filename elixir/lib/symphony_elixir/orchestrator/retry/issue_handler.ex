defmodule SymphonyElixir.Orchestrator.Retry.IssueHandler do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Retry.{Events, Scheduler}

  @spec handle(map(), String.t(), integer(), map(), keyword()) :: {:noreply, map()}
  def handle(state, issue_id, attempt, metadata, opts)
      when is_map(state) and is_binary(issue_id) and is_integer(attempt) and is_map(metadata) do
    dispatch_context = Keyword.fetch!(opts, :dispatch_context)
    dispatch_runtime = Keyword.fetch!(opts, :dispatch_runtime)
    dispatch_issue = Keyword.fetch!(opts, :dispatch_issue)
    release_issue_claim = Keyword.fetch!(opts, :release_issue_claim)
    cleanup_issue_workspace = Keyword.fetch!(opts, :cleanup_issue_workspace)
    emit_event = Keyword.get(opts, :emit_event)
    fetch_candidate_issues = Keyword.get(opts, :fetch_candidate_issues, fn -> {:ok, []} end)

    case fetch_candidate_issues.() do
      {:ok, issues} ->
        issues
        |> find_issue_by_id(issue_id)
        |> handle_retry_issue_lookup(
          state,
          issue_id,
          attempt,
          metadata,
          dispatch_context,
          dispatch_runtime,
          dispatch_issue,
          release_issue_claim,
          cleanup_issue_workspace,
          emit_event
        )

      {:error, reason} ->
        Events.emit(
          emit_event,
          :warning,
          :issue_retry_poll_failed,
          nil,
          state,
          %{
            issue_id: issue_id,
            issue_identifier: metadata[:identifier] || issue_id,
            attempt: attempt,
            run_id: metadata[:run_id],
            error: inspect(reason),
            worker_host: metadata[:worker_host],
            workspace_path: metadata[:workspace_path]
          }
        )

        {:noreply,
         Scheduler.schedule(
           state,
           issue_id,
           attempt + 1,
           Map.merge(metadata, %{error: "retry poll failed: #{inspect(reason)}"}),
           emit_event: emit_event
         )}
    end
  end

  def handle(state, _issue_id, _attempt, _metadata, _opts), do: {:noreply, state}

  defp handle_retry_issue_lookup(
         %Issue{} = issue,
         state,
         issue_id,
         attempt,
         metadata,
         dispatch_context,
         dispatch_runtime,
         dispatch_issue,
         release_issue_claim,
         cleanup_issue_workspace,
         emit_event
       ) do
    cond do
      Dispatch.terminal_issue_state?(issue, issue.state, dispatch_context) ->
        Events.released(emit_event, issue, state, attempt, metadata, "terminal")
        cleanup_workspace(cleanup_issue_workspace, issue.identifier, metadata)
        {:noreply, release_issue_claim.(state, issue_id)}

      Dispatch.retry_candidate_issue?(issue, dispatch_context) ->
        handle_active_retry(
          state,
          issue,
          attempt,
          metadata,
          dispatch_context,
          dispatch_runtime,
          dispatch_issue,
          emit_event
        )

      true ->
        Events.released(emit_event, issue, state, attempt, metadata, "not_active")
        {:noreply, release_issue_claim.(state, issue_id)}
    end
  end

  defp handle_retry_issue_lookup(
         nil,
         state,
         issue_id,
         _attempt,
         _metadata,
         _dispatch_context,
         _dispatch_runtime,
         _dispatch_issue,
         release_issue_claim,
         _cleanup_issue_workspace,
         emit_event
       ) do
    Events.emit(
      emit_event,
      :info,
      :issue_retry_released,
      nil,
      state,
      %{
        issue_id: issue_id,
        run_id: nil,
        skip_reason: "missing"
      }
    )

    {:noreply, release_issue_claim.(state, issue_id)}
  end

  defp handle_active_retry(
         state,
         issue,
         attempt,
         metadata,
         dispatch_context,
         dispatch_runtime,
         dispatch_issue,
         emit_event
       ) do
    if Dispatch.retry_candidate_issue?(issue, dispatch_context) and
         Dispatch.dispatch_slots_available?(issue, dispatch_runtime, dispatch_context) and
         runtime_worker_slots_available?(dispatch_runtime) do
      {:noreply, dispatch_issue.(state, issue, attempt, metadata[:worker_host])}
    else
      Events.emit(
        emit_event,
        :info,
        :issue_retry_dispatch_deferred,
        issue,
        state,
        %{
          attempt: attempt,
          run_id: metadata[:run_id],
          skip_reason: "no_available_slots",
          worker_host: metadata[:worker_host],
          workspace_path: metadata[:workspace_path]
        }
      )

      {:noreply,
       Scheduler.schedule(
         state,
         issue.id,
         attempt + 1,
         Map.merge(metadata, %{
           identifier: issue.identifier,
           error: "no available orchestrator slots"
         }),
         emit_event: emit_event
       )}
    end
  end

  defp find_issue_by_id(issues, issue_id) when is_list(issues) and is_binary(issue_id) do
    Enum.find(issues, fn
      %Issue{id: ^issue_id} ->
        true

      _other ->
        false
    end)
  end

  defp find_issue_by_id(_issues, _issue_id), do: nil

  defp cleanup_workspace(cleanup_issue_workspace, identifier, metadata)
       when is_function(cleanup_issue_workspace, 3) and is_binary(identifier) do
    cleanup_issue_workspace.(identifier, metadata[:worker_host], metadata[:workspace_path])
  end

  defp cleanup_workspace(_cleanup_issue_workspace, _identifier, _metadata), do: :ok

  defp runtime_worker_slots_available?(%{worker_slots_available?: available?})
       when is_boolean(available?),
       do: available?

  defp runtime_worker_slots_available?(_runtime), do: false
end
