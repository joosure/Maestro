defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.EventStreamSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{EventStream, SessionHandle}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec start_stream(SessionHandle.t(), pid(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_stream(%SessionHandle{} = handle, owner, opts \\ []) when is_pid(owner) and is_list(opts) do
    supervisor = Keyword.get(opts, :worker_daemon_event_stream_supervisor, __MODULE__)

    DynamicSupervisor.start_child(supervisor, {EventStream, handle: handle, owner: owner, opts: opts})
  catch
    :exit, {:noproc, _details} -> {:error, :worker_daemon_event_stream_supervisor_unavailable}
    :exit, reason -> {:error, {:worker_daemon_event_stream_supervisor_exit, reason}}
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
