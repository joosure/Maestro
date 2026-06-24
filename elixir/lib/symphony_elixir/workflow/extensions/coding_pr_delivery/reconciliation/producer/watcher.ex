defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher do
  @moduledoc """
  Bounded runtime producer for known change-proposal targets.

  The watcher only inspects targets that were previously registered by a safe
  runtime source. It never scans tracker source routes or repo-provider pull
  request lists to discover unrelated work.
  """

  use GenServer

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Result
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.State
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.TargetInspector

  @type run_result :: Result.t()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Options.merge_application_opts(opts) do
      {:ok, opts} ->
        case Keyword.fetch(opts, :name) do
          {:ok, nil} ->
            GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))

          {:ok, name} ->
            GenServer.start_link(__MODULE__, opts, name: name)

          :error ->
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec run_once(keyword()) :: run_result()
  def run_once(opts \\ [])

  def run_once(opts) do
    if Keyword.keyword?(opts) do
      case Options.context(opts) do
        {:ok, context} ->
          context.registry_module
          |> list_targets(context.registry, context.target_limit)
          |> Enum.reduce(Result.empty(), fn target, result ->
            TargetInspector.inspect_target(target, result, context)
          end)

        :skip ->
          Result.empty()

        {:error, _reason} ->
          Result.empty_error()
      end
    else
      Result.empty_error()
    end
  end

  @spec tick(GenServer.server()) :: run_result()
  def tick(server \\ __MODULE__) do
    GenServer.call(server, :tick)
  end

  @impl true
  def init(opts) do
    if Keyword.keyword?(opts) do
      {:ok, opts |> State.from_opts() |> State.schedule_if_enabled()}
    else
      {:stop, Diagnostics.invalid_options(opts)}
    end
  end

  @impl true
  def handle_call(:tick, _from, %State{} = state) do
    {:reply, run_once(State.to_opts(state)), state}
  end

  @impl true
  def handle_info(:poll, %State{} = state) do
    _result = run_once(State.to_opts(state))
    {:noreply, State.schedule_if_enabled(%{state | timer_ref: nil})}
  end

  defp list_targets(registry_module, registry, target_limit) do
    registry_module.list_targets(server: registry, limit: target_limit)
  end
end
