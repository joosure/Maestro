defmodule SymphonyElixir.Agent.Runtime.Handle do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Executor
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.SessionHandle
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @spec command(term(), iodata()) :: boolean()
  def command(port, data) when is_port(port), do: Port.command(port, data)
  def command(%SessionHandle{} = handle, data), do: SessionHandle.send_input(handle, data)
  def command(_handle, _data), do: false

  @spec alive?(term()) :: boolean()
  def alive?(port) when is_port(port), do: PlatformProcess.port_alive?(port)
  def alive?(%SessionHandle{} = handle), do: Executor.WorkerDaemon.alive?(handle)
  def alive?(_handle), do: false

  @spec close(term(), keyword()) :: :ok | {:error, term()}
  def close(handle, opts \\ [])

  def close(port, _opts) when is_port(port) do
    PlatformProcess.close_port(port)
  end

  def close(%SessionHandle{} = handle, opts) do
    Executor.WorkerDaemon.stop(handle, opts)
  end

  def close(_handle, _opts), do: :ok

  @spec os_pid(term()) :: pos_integer() | nil
  def os_pid(port) when is_port(port), do: PlatformProcess.port_os_pid(port)
  def os_pid(_handle), do: nil

  @spec safe_metadata(term()) :: map()
  def safe_metadata(%SessionHandle{} = handle), do: SessionHandle.safe_metadata(handle)
  def safe_metadata(_handle), do: %{}
end
