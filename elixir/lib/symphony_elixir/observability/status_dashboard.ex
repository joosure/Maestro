defmodule SymphonyElixir.Observability.StatusDashboard do
  @moduledoc """
  Renders a status snapshot for orchestrator and worker activity as a terminal UI.
  """

  use GenServer

  alias SymphonyElixir.AgentProvider

  alias SymphonyElixir.Observability.StatusDashboard.{
    Presenter,
    PresenterOptions,
    RenderFailure,
    RenderQueue,
    RuntimeConfig,
    Snapshot,
    Terminal,
    Throughput
  }

  @observability_pubsub Module.concat(["SymphonyElixirWeb", "Observability", "PubSub"])

  defstruct [
    :refresh_ms,
    :enabled,
    :render_interval_ms,
    :refresh_ms_override,
    :enabled_override,
    :render_interval_ms_override,
    :render_fun,
    :token_samples,
    :last_tps_second,
    :last_tps_value,
    :last_rendered_content,
    :last_rendered_at_ms,
    :pending_content,
    :flush_timer_ref,
    :last_snapshot_fingerprint
  ]

  @type t :: %__MODULE__{
          refresh_ms: pos_integer(),
          enabled: boolean(),
          render_interval_ms: pos_integer(),
          refresh_ms_override: pos_integer() | nil,
          enabled_override: boolean() | nil,
          render_interval_ms_override: pos_integer() | nil,
          render_fun: (String.t() -> term()),
          token_samples: [{integer(), integer()}],
          last_tps_second: integer() | nil,
          last_tps_value: float() | nil,
          last_rendered_content: String.t() | nil,
          last_rendered_at_ms: integer() | nil,
          pending_content: String.t() | nil,
          flush_timer_ref: reference() | nil,
          last_snapshot_fingerprint: term() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec notify_update(GenServer.name()) :: :ok
  def notify_update(server \\ __MODULE__) do
    observability_pubsub = @observability_pubsub
    observability_pubsub.broadcast_update()

    case GenServer.whereis(server) do
      pid when is_pid(pid) ->
        send(pid, :refresh)
        :ok

      _ ->
        :ok
    end
  end

  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    values = RuntimeConfig.initial_values(opts)
    schedule_tick(values.refresh_ms)

    {:ok,
     %__MODULE__{
       refresh_ms: values.refresh_ms,
       enabled: values.enabled,
       render_interval_ms: values.render_interval_ms,
       refresh_ms_override: values.refresh_ms_override,
       enabled_override: values.enabled_override,
       render_interval_ms_override: values.render_interval_ms_override,
       render_fun: values.render_fun,
       token_samples: [],
       last_tps_second: nil,
       last_tps_value: nil,
       last_rendered_content: nil,
       last_rendered_at_ms: nil,
       pending_content: nil,
       flush_timer_ref: nil,
       last_snapshot_fingerprint: nil
     }}
  end

  @spec render_offline_status() :: :ok
  def render_offline_status, do: Terminal.render_offline_status()

  @spec handle_info(term(), t()) :: {:noreply, t()}
  def handle_info(:tick, state) do
    state = RuntimeConfig.refresh(state)
    state = if state.enabled, do: maybe_render(state), else: state
    schedule_tick(state.refresh_ms)
    {:noreply, state}
  end

  def handle_info(:refresh, state) do
    state = RuntimeConfig.refresh(state)
    state = if state.enabled, do: maybe_render(state), else: state
    {:noreply, state}
  end

  def handle_info({:flush_render, timer_ref}, %{enabled: true, flush_timer_ref: timer_ref} = state) do
    now_ms = System.monotonic_time(:millisecond)
    state = RenderQueue.flush_pending(state, now_ms, &Terminal.render_content/3)
    {:noreply, state}
  end

  def handle_info({:flush_render, _timer_ref}, state), do: {:noreply, state}

  defp schedule_tick(refresh_ms), do: Process.send_after(self(), :tick, refresh_ms)

  defp maybe_render(state) do
    now_ms = System.monotonic_time(:millisecond)
    {snapshot_data, token_samples} = Snapshot.with_samples(state.token_samples, now_ms)
    current_tokens = Snapshot.total_tokens(snapshot_data)

    {tps_second, tps} =
      Throughput.throttled_tps(
        state.last_tps_second,
        state.last_tps_value,
        now_ms,
        token_samples,
        current_tokens
      )

    state =
      state
      |> Map.put(:token_samples, token_samples)
      |> Map.put(:last_tps_second, tps_second)
      |> Map.put(:last_tps_value, tps)

    if RenderQueue.render_due?(state, snapshot_data, now_ms) do
      content = format_snapshot_content(snapshot_data, tps)

      state
      |> RenderQueue.put_snapshot_fingerprint(snapshot_data)
      |> RenderQueue.enqueue(content, now_ms, &Terminal.render_content/3)
    else
      state
    end
  rescue
    error ->
      RenderFailure.emit(
        :dashboard_render_failed,
        "snapshot",
        error
      )

      state
  catch
    kind, reason ->
      RenderFailure.emit(
        :dashboard_render_failed,
        "snapshot",
        {kind, reason}
      )

      state
  end

  defp format_snapshot_content(snapshot_data, tps, terminal_columns_override \\ nil) do
    Presenter.format_snapshot_content(
      snapshot_data,
      tps,
      terminal_columns_override,
      PresenterOptions.format(snapshot_data)
    )
  end

  @doc false
  @spec present_agent_message(term()) :: String.t()
  defdelegate present_agent_message(message), to: AgentProvider, as: :present_message
end
