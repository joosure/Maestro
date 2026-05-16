defmodule SymphonyElixir.Agent.Runtime.Executor.LocalTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.Executor.Local
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  test "stop/2 closes the port and performs bounded OS process cleanup" do
    test_root = tmp_dir!("stop")

    on_exit(fn -> File.rm_rf(test_root) end)

    elixir = System.find_executable("elixir") || flunk("elixir executable is required for this test")

    command_spec =
      CommandSpec.new(
        argv: [
          elixir,
          "-e",
          ":os.set_signal(:sigterm, :ignore); IO.puts(\"ready\"); Process.sleep(:infinity)"
        ],
        cwd: test_root
      )

    target = Target.new(workspace_path: test_root)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024)

    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, 1_000
    assert Local.alive?(port)
    assert PlatformProcess.os_process_alive?(os_pid)

    assert :ok = Local.stop(port, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)

    refute Local.alive?(port)
    refute PlatformProcess.os_process_alive?(os_pid)
  end

  test "stop/2 terminates descendant processes in the local process group" do
    test_root = tmp_dir!("stop-descendants")

    on_exit(fn -> File.rm_rf(test_root) end)

    shell = System.find_executable("sh") || flunk("sh executable is required for this test")

    command_spec =
      CommandSpec.new(
        argv: [
          shell,
          "-c",
          "sleep 30 & child=$!; printf 'child=%s\\n' \"$child\"; wait"
        ],
        cwd: test_root
      )

    target = Target.new(workspace_path: test_root)

    assert {:ok, port} = Local.start(command_spec, target, line: 1024)
    assert_receive {^port, {:data, {:eol, "child=" <> child_pid_text}}}, 1_000
    {child_pid, ""} = Integer.parse(child_pid_text)
    assert PlatformProcess.os_process_alive?(child_pid)

    assert :ok = Local.stop(port, grace_ms: 50, kill_wait_ms: 1_000, poll_ms: 25)

    refute_eventually(fn -> PlatformProcess.os_process_alive?(child_pid) end)
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

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-local-executor-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
