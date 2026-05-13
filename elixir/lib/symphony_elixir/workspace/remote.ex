defmodule SymphonyElixir.Workspace.Remote do
  @moduledoc false

  alias SymphonyElixir.Platform.SSH

  @type worker_host :: String.t() | nil
  @type event_fields_builder :: (map(), Path.t() | nil, worker_host(), map() -> map())
  @type remote_runner :: (String.t() -> {:ok, {term(), integer()}} | {:error, term()})

  @spec workspace_options(worker_host(), event_fields_builder(), pos_integer()) :: keyword()
  def workspace_options(nil, event_fields_builder, _timeout_ms)
      when is_function(event_fields_builder, 4) do
    [event_fields: event_fields_builder]
  end

  def workspace_options(worker_host, event_fields_builder, timeout_ms)
      when is_binary(worker_host) and is_function(event_fields_builder, 4) and
             is_integer(timeout_ms) and timeout_ms > 0 do
    [
      event_fields: event_fields_builder,
      remote_runner: remote_command_runner(worker_host, timeout_ms)
    ]
  end

  @spec cleanup_options(map(), event_fields_builder()) :: keyword()
  def cleanup_options(config, event_fields_builder)
      when is_map(config) and is_function(event_fields_builder, 4) do
    hooks = Map.fetch!(config, :hooks)
    workspace = Map.fetch!(config, :workspace)
    worker = Map.fetch!(config, :worker)
    timeout_ms = Map.get(hooks, :timeout_ms, 30_000)

    [
      hooks: hooks,
      workspace_root: Map.fetch!(workspace, :root),
      ssh_hosts: Map.get(worker, :ssh_hosts, []),
      event_fields: event_fields_builder,
      remote_runner: fn worker_host -> remote_command_runner(worker_host, timeout_ms) end
    ]
  end

  @spec remote_command_runner(String.t(), pos_integer()) :: remote_runner()
  def remote_command_runner(worker_host, timeout_ms)
      when is_binary(worker_host) and is_integer(timeout_ms) and timeout_ms > 0 do
    fn script -> run_remote_command(worker_host, script, timeout_ms) end
  end

  @spec run_remote_command(String.t(), String.t(), pos_integer()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  def run_remote_command(worker_host, script, timeout_ms)
      when is_binary(worker_host) and is_binary(script) and is_integer(timeout_ms) and timeout_ms > 0 do
    task =
      Task.async(fn ->
        SSH.run(worker_host, script, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        result

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:workspace_hook_timeout, "remote_command", timeout_ms}}
    end
  end
end
