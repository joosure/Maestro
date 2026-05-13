defmodule SymphonyWorkerDaemon.OrphanSweeper.ProcessControl do
  @moduledoc false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @spec alive?(module(), pos_integer()) :: boolean()
  def alive?(process_module, os_pid) when is_atom(process_module) do
    if Code.ensure_loaded?(process_module) and function_exported?(process_module, :os_process_alive?, 1) do
      process_module.os_process_alive?(os_pid)
    else
      PlatformProcess.os_process_alive?(os_pid)
    end
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  @spec terminate(module(), pos_integer(), keyword()) :: map()
  def terminate(process_module, os_pid, opts) when is_atom(process_module) do
    if Code.ensure_loaded?(process_module) and function_exported?(process_module, :terminate_os_process, 2) do
      process_module.terminate_os_process(os_pid, opts)
    else
      PlatformProcess.terminate_os_process(os_pid, opts)
    end
  rescue
    _error -> %{os_pid: os_pid, signals_sent: [], alive?: true}
  catch
    _kind, _reason -> %{os_pid: os_pid, signals_sent: [], alive?: true}
  end
end
