defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap do
  @moduledoc """
  One-shot startup producer for review backlog candidates.

  Runtime-targeted reconciliation intentionally avoids broad provider scans
  during normal poll cycles. This producer bridges process restarts by doing a
  single bounded scan of the configured source routes and enqueueing those ids
  into the same runtime inbox used by webhooks, typed-tool events, and known
  target watchers.
  """

  use GenServer

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.StartupBacklogBootstrap.Runner

  @type run_result :: Events.run_result()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Options.merge_application_opts(opts) do
      {:ok, opts} ->
        case Keyword.fetch(opts, :name) do
          {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
          {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
          :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_once(keyword()) :: run_result()
  def run_once(opts \\ [])

  def run_once(opts) do
    if Keyword.keyword?(opts) do
      Runner.run_once(opts)
    else
      Events.failed(Diagnostics.invalid_options(opts), &Defaults.emit_event/3, System.monotonic_time(:millisecond))
    end
  end

  @impl true
  def init(opts) do
    if Keyword.keyword?(opts) do
      if Options.enabled?(opts), do: {:ok, opts, {:continue, :bootstrap}}, else: {:ok, opts}
    else
      {:stop, Diagnostics.invalid_options(opts)}
    end
  end

  @impl true
  def handle_continue(:bootstrap, opts) do
    _result = run_once(opts)
    {:noreply, opts}
  end
end
