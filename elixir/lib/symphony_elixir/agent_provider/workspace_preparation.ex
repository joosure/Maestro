defmodule SymphonyElixir.AgentProvider.WorkspacePreparation do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.ConfigResolver
  alias SymphonyElixir.AgentProvider.EventFields
  alias SymphonyElixir.AgentProvider.WorkspacePreparation.ToolContext
  alias SymphonyElixir.Observability.Logger, as: ObsLogger
  alias SymphonyElixir.Observability.OperationStatus

  @spec prepare_workspace(Path.t(), keyword()) :: :ok | {:error, term()}
  def prepare_workspace(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    config = ConfigResolver.effective_config(opts)
    started_at_ms = EventFields.monotonic_ms()

    result =
      try do
        with {:ok, opts} <- ToolContext.put(opts) do
          ConfigResolver.adapter_for_config(config).prepare_workspace(config, workspace, opts)
        end
      rescue
        exception ->
          {:error, exception}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end

    handle_result(result, config, workspace, opts, started_at_ms)
  end

  defp handle_result(:ok, config, workspace, opts, started_at_ms) do
    ObsLogger.emit(
      :info,
      :agent_provider_workspace_prepared,
      EventFields.workspace(config, workspace, opts, %{
        operation: "prepare_workspace",
        status: OperationStatus.prepared(),
        duration_ms: EventFields.elapsed_ms(started_at_ms)
      })
    )

    :ok
  end

  defp handle_result({:error, reason} = error, config, workspace, opts, started_at_ms) do
    emit_prepare_failed(config, workspace, opts, started_at_ms, reason)
    error
  end

  defp handle_result(other, config, workspace, opts, started_at_ms) do
    reason = {:unexpected_prepare_workspace_result, other}
    emit_prepare_failed(config, workspace, opts, started_at_ms, reason)
    {:error, reason}
  end

  defp emit_prepare_failed(config, workspace, opts, started_at_ms, reason) do
    ObsLogger.emit(
      :error,
      :agent_provider_workspace_prepare_failed,
      EventFields.workspace(
        config,
        workspace,
        opts,
        %{
          operation: "prepare_workspace",
          status: OperationStatus.failed(),
          duration_ms: EventFields.elapsed_ms(started_at_ms)
        }
        |> Map.merge(EventFields.error(reason))
      )
    )
  end
end
