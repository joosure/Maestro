defmodule SymphonyElixir.Agent.Runtime.LocalProcess.RegistryTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, LocalProcess, Target}
  alias SymphonyElixir.Agent.Runtime.Executor.Local
  alias SymphonyElixir.Agent.Runtime.LocalProcess.Ledger
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @port_receive_timeout 5_000

  defmodule FailingProcessControl do
    def terminate_os_process_tree(_os_pid, _opts), do: %{alive?: true, signals_sent: ["TERM", "KILL"]}
    def os_process_alive?(_os_pid), do: true
    def os_process_command(_os_pid), do: {:ok, "sleep 60"}
  end

  test "local executor registers a process and normal stop removes its ledger record" do
    root = tmp_dir!("normal-stop-ledger")
    workspace = tmp_dir!("normal-stop-workspace")
    registry = unique_name("NormalStopRegistry")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    start_supervised!({LocalProcess, name: registry, ledger_root: root, sweep_on_start?: false})

    command_spec = shell_command("printf 'ready\\n'; sleep 60", workspace)
    target = Target.new(workspace_path: workspace)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024, local_process_registry: registry, provider_kind: "test_provider")
    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout

    assert [%{"os_pid" => ^os_pid, "provider_kind" => "test_provider"}] = Ledger.list_records(root)

    assert :ok = Local.stop(port, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25, local_process_registry: registry)

    assert [] = Ledger.list_records(root)
    refute_eventually(fn -> PlatformProcess.os_process_alive?(os_pid) end)
  end

  test "registry shutdown terminates still-registered local process trees" do
    root = tmp_dir!("shutdown-ledger")
    workspace = tmp_dir!("shutdown-workspace")
    registry = unique_name("ShutdownRegistry")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    pid = start_supervised!({LocalProcess, name: registry, ledger_root: root, sweep_on_start?: false})

    command_spec = shell_command("printf 'ready\\n'; sleep 60", workspace)
    target = Target.new(workspace_path: workspace)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024, local_process_registry: registry)
    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout
    assert [_record] = Ledger.list_records(root)

    GenServer.stop(pid, :normal, 5_000)

    assert [] = Ledger.list_records(root)
    refute_eventually(fn -> PlatformProcess.os_process_alive?(os_pid) end)
  end

  test "registry shutdown keeps ledger records when process termination fails" do
    root = tmp_dir!("shutdown-failure-ledger")
    workspace = tmp_dir!("shutdown-failure-workspace")
    registry = unique_name("ShutdownFailureRegistry")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    pid =
      start_supervised!({LocalProcess, name: registry, ledger_root: root, process_module: FailingProcessControl, sweep_on_start?: false})

    command_spec = shell_command("printf 'ready\\n'; sleep 60", workspace)
    target = Target.new(workspace_path: workspace)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024, local_process_registry: registry)
    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout

    GenServer.stop(pid, :normal, 5_000)

    assert [%{"os_pid" => ^os_pid}] = Ledger.list_records(root)
    assert PlatformProcess.os_process_alive?(os_pid)

    PlatformProcess.terminate_os_process_tree(os_pid, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)
    PlatformProcess.close_port(port)
  end

  test "startup sweeper terminates stale records whose owner process is gone" do
    root = tmp_dir!("sweep-stale-ledger")
    workspace = tmp_dir!("sweep-stale-workspace")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    command_spec = shell_command("printf 'ready\\n'; sleep 60", workspace)
    target = Target.new(workspace_path: workspace)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024, local_process_registry: nil)
    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout

    write_stale_record!(root, os_pid, workspace)

    result = LocalProcess.sweep(ledger_root: root, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)

    assert result.terminated == 1
    assert [] = Ledger.list_records(root)
    refute_eventually(fn -> PlatformProcess.os_process_alive?(os_pid) end)
    PlatformProcess.close_port(port)
  end

  test "startup sweeper loads process control module before checking callbacks" do
    root = tmp_dir!("sweep-unloaded-process-module-ledger")
    workspace = tmp_dir!("sweep-unloaded-process-module-workspace")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    process_module = compile_unloaded_process_module!(tmp_dir!("sweep-unloaded-process-module-code"))
    write_stale_record!(root, 999_999_998, workspace)

    result = LocalProcess.sweep(ledger_root: root, process_module: process_module)

    assert result.terminated == 1
    assert result.already_exited == 0
    assert [] = Ledger.list_records(root)
  end

  test "startup sweeper skips records whose owner process is still alive" do
    root = tmp_dir!("sweep-live-owner-ledger")
    workspace = tmp_dir!("sweep-live-owner-workspace")

    on_exit(fn -> File.rm_rf(root) end)
    on_exit(fn -> File.rm_rf(workspace) end)

    command_spec = shell_command("printf 'ready\\n'; sleep 60", workspace)
    target = Target.new(workspace_path: workspace)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024, local_process_registry: nil)
    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout

    write_owned_record!(root, os_pid, workspace)

    result = LocalProcess.sweep(ledger_root: root, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)

    assert result.skipped == 1
    assert [_record] = Ledger.list_records(root)
    assert PlatformProcess.os_process_alive?(os_pid)

    PlatformProcess.terminate_os_process_tree(os_pid, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)
    PlatformProcess.close_port(port)
  end

  defp shell_command(command, cwd) do
    CommandSpec.new(command: command, cwd: cwd)
  end

  defp write_stale_record!(root, os_pid, workspace) do
    write_record!(root, os_pid, workspace, 999_999_999)
  end

  defp write_owned_record!(root, os_pid, workspace) do
    write_record!(root, os_pid, workspace, Ledger.owner_os_pid())
  end

  defp write_record!(root, os_pid, workspace, owner_os_pid) do
    id = Ledger.new_id()

    record =
      Ledger.build_record(id, os_pid, %{
        provider_kind: "test_provider",
        workspace: workspace,
        cwd: workspace,
        command: %{shape: "command", command: "shell", argc: 1},
        command_match_tokens: []
      })
      |> Map.put("owner_os_pid", owner_os_pid)

    assert :ok = Ledger.write_record(root, record)
  end

  defp compile_unloaded_process_module!(beam_dir) do
    File.mkdir_p!(beam_dir)
    module = __MODULE__.ProcessControlFixture
    erlang_module = Atom.to_string(module)
    source_path = Path.join(beam_dir, "#{module}.erl")

    File.write!(source_path, """
    -module('#{erlang_module}').
    -export(['terminate_os_process_tree'/2, 'os_process_alive?'/1, 'os_process_command'/1]).

    'terminate_os_process_tree'(_OsPid, _Opts) -> \#{'alive?' => false}.
    'os_process_alive?'(999999998) -> true;
    'os_process_alive?'(_OsPid) -> false.
    'os_process_command'(_OsPid) -> {ok, <<"opencode serve --hostname 127.0.0.1">>}.
    """)

    assert {:ok, ^module, []} =
             :compile.file(String.to_charlist(source_path), [:return_errors, :return_warnings, {:outdir, String.to_charlist(beam_dir)}])

    true = :code.add_patha(String.to_charlist(beam_dir))
    :code.purge(module)
    :code.delete(module)
    false = :code.is_loaded(module)

    module
  end

  defp wait_for_port_os_pid!(port, attempts_remaining \\ 20)

  defp wait_for_port_os_pid!(port, attempts_remaining) when attempts_remaining > 0 do
    case PlatformProcess.port_os_pid(port) do
      os_pid when is_integer(os_pid) and os_pid > 0 ->
        os_pid

      _none ->
        Process.sleep(25)
        wait_for_port_os_pid!(port, attempts_remaining - 1)
    end
  end

  defp wait_for_port_os_pid!(_port, 0), do: flunk("port os_pid was not available")

  defp refute_eventually(fun, attempts \\ 40)

  defp refute_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      Process.sleep(25)
      refute_eventually(fun, attempts - 1)
    else
      refute fun.()
    end
  end

  defp refute_eventually(_fun, 0), do: flunk("condition remained true")

  defp unique_name("NormalStopRegistry"), do: __MODULE__.NormalStopRegistry
  defp unique_name("ShutdownRegistry"), do: __MODULE__.ShutdownRegistry
  defp unique_name("ShutdownFailureRegistry"), do: __MODULE__.ShutdownFailureRegistry

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-local-process-registry-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
