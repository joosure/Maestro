defmodule SymphonyElixir.Agent.Runner.SessionLoop do
  @moduledoc false

  alias SymphonyElixir.Agent.Runner.{ActiveSessions, ProviderOptions, RunContext, SessionCleanup, TurnLoop}
  alias SymphonyElixir.{AgentProvider, Config, Tracker}

  @type worker_host :: String.t() | nil

  @spec run(Path.t(), term(), term(), keyword(), worker_host(), String.t()) :: :ok | {:error, term()}
  def run(workspace, issue, update_recipient, opts, worker_host, run_id) do
    max_turns = Keyword.get(opts, :max_turns, Config.settings!().agent.execution.max_turns)

    issue_state_fetcher =
      Keyword.get(opts, :issue_state_fetcher, &Tracker.fetch_issue_states_by_ids/1)

    case AgentProvider.start_session(workspace, start_session_opts(opts, worker_host, run_id, issue)) do
      {:ok, session} ->
        run_with_session(
          session,
          workspace,
          issue,
          update_recipient,
          opts,
          issue_state_fetcher,
          worker_host,
          run_id,
          max_turns
        )

      {:error, _reason} = error ->
        RunContext.remote_startup_result(error, worker_host)
    end
  end

  defp start_session_opts(opts, worker_host, run_id, issue) when is_list(opts) do
    opts
    |> Keyword.drop([:issue_state_fetcher, :max_turns])
    |> Keyword.merge(
      worker_host: worker_host,
      run_id: run_id,
      issue: issue,
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier)
    )
  end

  defp run_with_session(
         session,
         workspace,
         issue,
         update_recipient,
         opts,
         issue_state_fetcher,
         worker_host,
         run_id,
         max_turns
       ) do
    ActiveSessions.register(session, %{
      issue: issue,
      worker_host: worker_host,
      workspace: workspace,
      run_id: run_id
    })

    result =
      TurnLoop.run(
        session,
        workspace,
        issue,
        update_recipient,
        opts,
        issue_state_fetcher,
        worker_host,
        run_id,
        1,
        max_turns
      )

    cleanup_session(
      session,
      SessionCleanup.stop_options(session, result, issue),
      issue,
      worker_host,
      workspace,
      run_id,
      "normal"
    )

    result
  rescue
    exception ->
      cleanup_session(
        session,
        AgentProvider.failed_session_stop_options(
          issue,
          inspect(exception),
          ProviderOptions.from_session(session)
        ),
        issue,
        worker_host,
        workspace,
        run_id,
        "exception"
      )

      reraise(exception, __STACKTRACE__)
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__

      cleanup_session(
        session,
        AgentProvider.failed_session_stop_options(
          issue,
          inspect({kind, reason}),
          ProviderOptions.from_session(session)
        ),
        issue,
        worker_host,
        workspace,
        run_id,
        "exception"
      )

      :erlang.raise(kind, reason, stacktrace)
  end

  defp cleanup_session(session, stop_opts, issue, worker_host, workspace, run_id, reason) do
    case ActiveSessions.claim_current_cleanup() do
      :ok ->
        SessionCleanup.stop(session, stop_opts, issue, worker_host, workspace, run_id, reason)

      :not_registered ->
        :ok

      :unavailable ->
        SessionCleanup.stop(session, stop_opts, issue, worker_host, workspace, run_id, reason)
    end
  end
end
