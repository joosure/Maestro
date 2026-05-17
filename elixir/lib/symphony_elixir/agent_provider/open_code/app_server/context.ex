defmodule SymphonyElixir.AgentProvider.OpenCode.AppServer.Context do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Kinds
  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.Diagnostics
  alias SymphonyElixir.AgentProvider.OpenCode.Settings

  @provider_kind Kinds.opencode()

  @spec startup(Path.t(), Settings.t(), map(), String.t() | nil) :: map()
  def startup(workspace, %Settings{} = settings, metadata, run_id) when is_map(metadata) do
    metadata
    |> Map.take([:agent_process_pid])
    |> Map.merge(%{
      agent_provider_kind: @provider_kind,
      workspace: workspace,
      agent: settings.agent,
      model: settings.model,
      variant: settings.variant,
      read_timeout_ms: settings.read_timeout_ms,
      turn_timeout_ms: settings.turn_timeout_ms,
      stall_timeout_ms: settings.stall_timeout_ms,
      run_id: run_id,
      correlation_id: run_id
    })
    |> Diagnostics.compact_details()
  end

  @spec session(map()) :: map()
  def session(session) when is_map(session) do
    session.metadata
    |> Map.take([:agent_process_pid])
    |> Map.merge(%{
      agent_provider_kind: @provider_kind,
      workspace: session.workspace,
      base_url: session.base_url,
      session_id: session.session_id,
      thread_id: session.thread_id,
      agent: session.settings.agent,
      model: session.settings.model,
      variant: session.settings.variant,
      read_timeout_ms: session.settings.read_timeout_ms,
      turn_timeout_ms: session.settings.turn_timeout_ms,
      stall_timeout_ms: session.settings.stall_timeout_ms,
      run_id: session.run_id,
      correlation_id: session.run_id
    })
    |> Diagnostics.compact_details()
  end
end
