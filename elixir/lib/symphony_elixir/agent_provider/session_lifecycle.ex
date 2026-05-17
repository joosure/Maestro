defmodule SymphonyElixir.AgentProvider.SessionLifecycle do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential
  alias SymphonyElixir.AgentProvider.Capabilities
  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.EventFields
  alias SymphonyElixir.AgentProvider.RuntimeStart
  alias SymphonyElixir.AgentProvider.Session
  alias SymphonyElixir.AgentProvider.SessionContext
  alias SymphonyElixir.AgentProvider.TurnResult
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus

  @spec start_session(Path.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    config = ConfigResolver.effective_config(opts)
    started_at_ms = EventFields.monotonic_ms()

    case RuntimeStart.provider_start_opts(config, workspace, opts) do
      {:ok, start_opts} ->
        start_provider_session(config, workspace, opts, start_opts, started_at_ms)

      {:error, _reason} = error ->
        error
    end
  end

  @spec run_turn(term(), String.t(), map(), keyword()) :: {:ok, TurnResult.t()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []) do
    session = SessionContext.normalize_session(session)
    config = SessionContext.config_from_session(session, opts)

    case ConfigResolver.adapter_for_config(config).run_turn(config, session, prompt, issue, opts) do
      {:ok, result} -> {:ok, TurnResult.new(result)}
      {:error, _reason} = error -> error
    end
  end

  @spec stop_session(term(), keyword()) :: :ok | {:error, term()}
  def stop_session(session, opts \\ []) do
    session = SessionContext.normalize_session(session)
    config = SessionContext.config_from_session(session, opts)
    started_at_ms = EventFields.monotonic_ms()

    result =
      try do
        ConfigResolver.adapter_for_config(config).stop_session(config, session, opts)
      rescue
        exception ->
          {:error, exception}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end

    :ok = Credential.release_provider_start(config, session, opts)
    handle_stop_result(result, session, config, opts, started_at_ms)
  end

  @spec session_stop_options(term(), term(), keyword()) :: keyword()
  def session_stop_options(result, issue, opts \\ []) do
    config = ConfigResolver.effective_config(opts)

    ConfigResolver.adapter_for_config(config).session_stop_options(config, result, issue)
  end

  @spec failed_session_stop_options(term(), String.t(), keyword()) :: keyword()
  def failed_session_stop_options(issue, error, opts \\ []) when is_binary(error) do
    config = ConfigResolver.effective_config(opts)

    ConfigResolver.adapter_for_config(config).failed_session_stop_options(config, issue, error)
  end

  defp start_provider_session(config, workspace, opts, start_opts, started_at_ms) do
    case ConfigResolver.adapter_for_config(config).start_session(config, workspace, start_opts) do
      {:ok, session} ->
        session =
          session
          |> SessionContext.normalize_session()
          |> Session.put_config(config)
          |> SessionContext.put_start_resources(start_opts)
          |> SessionContext.normalize_session_context(config, workspace, opts)

        ObsLogger.emit(
          :info,
          :agent_session_started,
          EventFields.session(session, config, opts, %{
            operation: "start_session",
            status: OperationStatus.started(),
            stateful: Capabilities.stateful_config?(config),
            session_type: Capabilities.session_type(config),
            duration_ms: EventFields.elapsed_ms(started_at_ms)
          })
        )

        {:ok, session}

      {:error, _reason} = error ->
        :ok =
          Credential.release_provider_start(
            config,
            %{
              agent_credential_lease: Keyword.get(start_opts, :agent_credential_lease),
              agent_credential_material: Keyword.get(start_opts, :agent_credential_material)
            },
            opts
          )

        error
    end
  end

  defp handle_stop_result(:ok, session, config, opts, started_at_ms) do
    ObsLogger.emit(
      :info,
      :agent_session_stopped,
      EventFields.session(session, config, opts, %{
        operation: "stop_session",
        status: OperationStatus.stopped(),
        stateful: Capabilities.stateful_config?(config),
        session_type: Capabilities.session_type(config),
        duration_ms: EventFields.elapsed_ms(started_at_ms)
      })
    )

    :ok
  end

  defp handle_stop_result({:error, reason} = error, session, config, opts, started_at_ms) do
    emit_stop_failed(session, config, opts, started_at_ms, reason)
    error
  end

  defp handle_stop_result(other, session, config, opts, started_at_ms) do
    reason = {:unexpected_stop_session_result, other}
    emit_stop_failed(session, config, opts, started_at_ms, reason)
    {:error, reason}
  end

  defp emit_stop_failed(session, config, opts, started_at_ms, reason) do
    ObsLogger.emit(
      :error,
      :agent_session_stop_failed,
      EventFields.session(
        session,
        config,
        opts,
        %{
          operation: "stop_session",
          status: OperationStatus.failed(),
          stateful: Capabilities.stateful_config?(config),
          session_type: Capabilities.session_type(config),
          duration_ms: EventFields.elapsed_ms(started_at_ms)
        }
        |> Map.merge(EventFields.error(reason))
      )
    )
  end
end
