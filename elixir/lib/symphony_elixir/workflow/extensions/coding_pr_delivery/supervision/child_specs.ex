defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision.ChildSpecs do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Supervision.Options

  @spec children(Options.t()) :: [Supervisor.child_spec() | module() | {module(), term()}]
  def children(%Options{} = options) do
    [
      Inbox,
      {KnownTarget.Registry, options.known_target_registry_opts},
      StartupBacklogBootstrap,
      {Watcher, options.watcher_opts}
    ]
  end

  @spec failing_child(map()) :: Supervisor.child_spec()
  def failing_child(reason) when is_map(reason) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_error, [reason]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc false
  @spec start_error(map()) :: {:error, map()}
  def start_error(reason) when is_map(reason), do: {:error, reason}
end
