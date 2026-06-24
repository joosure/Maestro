defmodule SymphonyElixir.Application do
  @moduledoc """
  OTP application entrypoint that starts core supervisors and workers.
  """

  use Application

  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.{LogFile, StatusDashboard}
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Orchestrator.WorkflowExtensionRuntimeCommands
  alias SymphonyElixir.Storage.Config, as: PlatformStorageConfig
  alias SymphonyElixir.Storage.TableCatalog
  alias SymphonyElixir.Workflow.Extension.Contributions
  alias SymphonyElixir.Workflow.Extension.Registry
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry, as: ReadinessPolicyRegistry

  @component "application"

  @impl true
  def start(_type, _args) do
    :ok = LogFile.configure()
    :ok = Registry.validate!()
    :ok = ReadinessPolicyRegistry.validate!()

    children =
      [
        {Phoenix.PubSub, name: SymphonyElixir.PubSub},
        storage_children(),
        SymphonyElixir.Agent.Runtime.LocalProcess,
        SymphonyElixir.Agent.Runner.ActiveSessions,
        {Task.Supervisor, name: SymphonyElixir.TaskSupervisor},
        SymphonyElixir.Observability.EventStore,
        SymphonyElixir.Workflow.Runtime.Store,
        SymphonyElixir.Workflow.StateTransitionReadiness.Store,
        SymphonyElixir.Agent.ExecutionPlan.Store,
        SymphonyElixir.Workflow.StructuredExecutionPlan.Store,
        SymphonyElixir.Tracker.WorkpadRegistry,
        SymphonyElixir.Orchestrator.BlockedResourceRegistry,
        workflow_extension_children(),
        SymphonyElixir.Agent.DynamicTool.Bridge.Registry,
        {SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy, SymphonyElixir.Workflow.StateTransitionReadiness.TypedToolFailurePolicy.agent_options()},
        SymphonyElixir.Agent.Quota.Poller,
        SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStreamSupervisor,
        SymphonyElixir.Agent.Runtime.WorkerDaemon.EndpointState,
        SymphonyElixir.Orchestrator,
        SymphonyElixir.HttpServer,
        SymphonyElixir.Observability.StatusDashboard
      ]
      |> List.flatten()

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
            component: @component,
            result_summary: "children=#{length(children)}"
          }
        )

        result

      {:error, reason} = error ->
        ObservabilityLogger.emit(
          :error,
          :service_start_failed,
          %{
            component: @component,
            error: inspect(reason)
          }
        )

        error
    end
  end

  defp workflow_extension_children do
    Contributions.children!(
      workflow_scope: workflow_scope_value(),
      command_handler: &WorkflowExtensionRuntimeCommands.handle/1
    )
  end

  defp workflow_scope_value do
    case Config.settings() do
      {:ok, settings} ->
        RuntimeContext.new!(settings, %{}).workflow_scope

      {:error, _reason} ->
        nil
    end
  end

  defp storage_children do
    if PlatformStorageConfig.sqlite?() do
      :ok = TableCatalog.validate!()

      [
        SymphonyElixir.Storage.Repo,
        SymphonyElixir.Storage.Migrator
      ]
    else
      []
    end
  end

  @impl true
  def stop(_state) do
    ObservabilityLogger.emit(
      :info,
      :service_stopped,
      %{
        component: @component
      }
    )

    StatusDashboard.render_offline_status()
    :ok
  end
end
