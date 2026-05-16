defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  alias SymphonyElixir.Observability.{LogFile, StatusDashboard}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger

  @impl true
  def start(_type, _args) do
    :ok = LogFile.configure()

    children = [
      {Phoenix.PubSub, name: SymphonyElixir.PubSub},
      {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
      SymphonyElixir.Observability.EventStore,
      SymphonyElixir.Workflow.Runtime.Store,
      SymphonyElixir.ChangeProposalReconciliation.CandidateInbox,
      SymphonyElixir.ChangeProposalReconciliation.KnownTarget.Registry,
      SymphonyElixir.ChangeProposalReconciliation.Producer.Watcher,
      SymphonyElixir.Agent.DynamicTool.BridgeRegistry,
      SymphonyElixir.Agent.Quota.Poller,
      SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStreamSupervisor,
      SymphonyElixir.Agent.Runtime.WorkerDaemon.EndpointState,
      SymphonyElixir.Orchestrator,
      SymphonyElixir.HttpServer,
      SymphonyElixir.Observability.StatusDashboard
    ]

    case Supervisor.start_link(
           children,
           strategy: :one_for_one,
           name: SymphonyElixir.Supervisor
         ) do
      {:ok, _pid} = result ->
        ObservabilityLogger.emit(
          :info,
          :service_started,
          %{
            component: "application",
            result_summary: "children=#{length(children)}"
          }
        )

        result

      {:error, reason} = error ->
        ObservabilityLogger.emit(
          :error,
          :service_start_failed,
          %{
            component: "application",
            error: inspect(reason)
          }
        )

        error
    end
  end

  @impl true
  def stop(_state) do
    ObservabilityLogger.emit(
      :info,
      :service_stopped,
      %{
        component: "application"
      }
    )

    StatusDashboard.render_offline_status()
    :ok
  end
end
