defmodule SymphonyElixir.Agent.Runtime.LocalProcess.Registry do
  @moduledoc false

  use GenServer

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.LocalProcess.{Ledger, Sweeper}
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @default_grace_ms 500
  @default_kill_wait_ms 500
  @default_poll_ms 25

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec register(port(), CommandSpec.t(), Target.t(), keyword(), GenServer.server()) :: :ok
  def register(port, %CommandSpec{} = command_spec, %Target{} = target, opts, server \\ __MODULE__)
      when is_port(port) and is_list(opts) do
    call_if_running(server, {:register, port, command_spec, target, opts})
  end

  @spec unregister(term(), GenServer.server()) :: :ok
  def unregister(handle, server \\ __MODULE__)

  def unregister(port, server) when is_port(port) do
    call_if_running(server, {:unregister, port})
  end

  def unregister(_handle, _server), do: :ok

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    root = Ledger.root(opts)
    process_module = Keyword.get(opts, :process_module, PlatformProcess)

    if Keyword.get(opts, :sweep_on_start?, true) do
      _ = Sweeper.sweep(Keyword.merge(opts, ledger_root: root, process_module: process_module))
    end

    {:ok, %{root: root, process_module: process_module, entries: %{}}}
  end

  @impl true
  def handle_call({:register, port, command_spec, target, opts}, _from, state) do
    state =
      case PlatformProcess.port_os_pid(port) do
        os_pid when is_integer(os_pid) and os_pid > 0 ->
          register_entry(port, os_pid, command_spec, target, opts, state)

        _os_pid ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:unregister, port}, _from, state) do
    {:reply, :ok, unregister_entry(port, state)}
  end

  @impl true
  def terminate(_reason, state) do
    state
    |> Map.get(:entries, %{})
    |> Map.values()
    |> Enum.each(&terminate_entry(&1, state))

    :ok
  end

  defp register_entry(port, os_pid, command_spec, target, opts, state) do
    state = unregister_entry(port, state)
    id = Ledger.new_id()

    record =
      Ledger.build_record(id, os_pid, %{
        provider_kind: metadata_value(command_spec, target, opts, :provider_kind),
        run_id: metadata_value(command_spec, target, opts, :run_id),
        session_id: metadata_value(command_spec, target, opts, :session_id),
        workspace: target.workspace_path,
        worker_host: target.worker_host,
        cwd: command_spec.cwd || target.workspace_path,
        command: sanitized_command(command_spec),
        command_match_tokens: command_match_tokens(command_spec)
      })

    _ = Ledger.write_record(state.root, record)

    put_in(state, [:entries, port], %{
      id: id,
      os_pid: os_pid,
      port: port,
      record: record
    })
  end

  defp unregister_entry(port, state) do
    case Map.pop(state.entries, port) do
      {nil, entries} ->
        %{state | entries: entries}

      {%{id: id}, entries} ->
        Ledger.delete_record(state.root, id)
        %{state | entries: entries}
    end
  end

  defp terminate_entry(%{os_pid: os_pid, port: port, id: id}, state) do
    termination =
      state.process_module.terminate_os_process_tree(os_pid,
        process_group?: true,
        grace_ms: @default_grace_ms,
        kill_wait_ms: @default_kill_wait_ms,
        poll_ms: @default_poll_ms
      )

    PlatformProcess.close_port(port)

    if not Map.get(termination, :alive?) do
      Ledger.delete_record(state.root, id)
    end

    :ok
  rescue
    _error -> :ok
  end

  defp call_if_running(server, request) do
    case resolve_server(server) do
      nil -> :ok
      pid when is_pid(pid) -> GenServer.call(pid, request, 5_000)
    end
  catch
    :exit, _reason -> :ok
  end

  defp resolve_server(server) when is_atom(server), do: Process.whereis(server)
  defp resolve_server(server) when is_pid(server), do: server
  defp resolve_server(_server), do: nil

  defp metadata_value(%CommandSpec{} = command_spec, %Target{} = target, opts, key) do
    Keyword.get(opts, key) || Map.get(command_spec.metadata, key) || Map.get(command_spec.metadata, Atom.to_string(key)) ||
      Map.get(target.metadata, key) || Map.get(target.metadata, Atom.to_string(key))
  end

  defp sanitized_command(%CommandSpec{argv: [command | args]}) do
    %{
      shape: "command_argv",
      command: Path.basename(command),
      argc: length(args) + 1
    }
  end

  defp sanitized_command(%CommandSpec{command: command}) when is_binary(command) do
    %{
      shape: "command",
      command: "shell",
      argc: 1
    }
  end

  defp sanitized_command(%CommandSpec{}), do: %{shape: "unset", argc: 0}

  defp command_match_tokens(%CommandSpec{argv: [command | args]}) do
    [Path.basename(command) | Enum.take(args, 2)]
    |> Enum.filter(&safe_match_token?/1)
  end

  defp command_match_tokens(%CommandSpec{command: _command}), do: []
  defp command_match_tokens(%CommandSpec{}), do: []

  defp safe_match_token?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and not String.contains?(trimmed, ["\n", "\r", <<0>>]) and not secret_like_token?(trimmed)
  end

  defp safe_match_token?(_value), do: false

  defp secret_like_token?(token) do
    token =~ ~r/(token|secret|api[_-]?key|password|credential)/i
  end
end
