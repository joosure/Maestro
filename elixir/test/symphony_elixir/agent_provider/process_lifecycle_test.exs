defmodule SymphonyElixir.AgentProvider.ProcessLifecycleTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentProvider.ClaudeCode.AppServer.ProcessLifecycle, as: ClaudeCodeLifecycle
  alias SymphonyElixir.AgentProvider.Codex.AppServer.ProcessLifecycle, as: CodexLifecycle
  alias SymphonyElixir.AgentProvider.OpenCode.AppServer.ProcessLifecycle, as: OpenCodeLifecycle
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @port_receive_timeout 5_000

  test "Codex process lifecycle terminates provider descendants" do
    assert_provider_descendant_stopped(fn port ->
      CodexLifecycle.stop_port(port, %{run_id: "run-codex-process-tree", correlation_id: "run-codex-process-tree"})
    end)
  end

  test "Claude Code process lifecycle terminates provider descendants" do
    assert_provider_descendant_stopped(&ClaudeCodeLifecycle.stop_port/1)
  end

  test "OpenCode process lifecycle terminates provider descendants" do
    assert_provider_descendant_stopped(&OpenCodeLifecycle.stop_port/1)
  end

  defp assert_provider_descendant_stopped(stop_fun) when is_function(stop_fun, 1) do
    test_root = tmp_dir!("provider-process-tree")

    File.mkdir_p!(test_root)
    on_exit(fn -> File.rm_rf(test_root) end)

    executable = Path.join(test_root, "provider-with-child")
    child_pid_file = Path.join(test_root, "child.pid")

    File.write!(executable, """
    #!/bin/sh
    sleep 60 &
    printf '%s\\n' "$!" > "#{child_pid_file}"
    printf 'ready\\n'
    wait
    """)

    File.chmod!(executable, 0o755)

    assert {:ok, port} = PlatformProcess.start_argv([executable], cwd: test_root, line: 1024)
    parent_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout

    child_pid = wait_for_pid_file!(child_pid_file)

    try do
      assert PlatformProcess.os_process_alive?(parent_pid)
      assert PlatformProcess.os_process_alive?(child_pid)

      assert :ok = stop_fun.(port)
      refute wait_for_os_process_alive?(child_pid)
    after
      PlatformProcess.terminate_os_process_tree(parent_pid, initial_signal?: false, grace_ms: 50, kill_wait_ms: 250)
      PlatformProcess.terminate_os_process(child_pid, initial_signal?: false, grace_ms: 50, kill_wait_ms: 250)
      PlatformProcess.close_port(port)
    end
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

  defp wait_for_pid_file!(path, attempts_remaining \\ 40)

  defp wait_for_pid_file!(path, attempts_remaining) when attempts_remaining > 0 do
    case File.read(path) do
      {:ok, contents} ->
        case Integer.parse(String.trim(contents)) do
          {pid, ""} when pid > 0 -> pid
          _other -> retry_pid_file(path, attempts_remaining)
        end

      {:error, _reason} ->
        retry_pid_file(path, attempts_remaining)
    end
  end

  defp wait_for_pid_file!(_path, 0), do: flunk("pid file was not written")

  defp retry_pid_file(path, attempts_remaining) do
    Process.sleep(25)
    wait_for_pid_file!(path, attempts_remaining - 1)
  end

  defp wait_for_os_process_alive?(os_pid, attempts_remaining \\ 40)

  defp wait_for_os_process_alive?(os_pid, attempts_remaining) when attempts_remaining > 0 do
    if PlatformProcess.os_process_alive?(os_pid) do
      Process.sleep(25)
      wait_for_os_process_alive?(os_pid, attempts_remaining - 1)
    else
      false
    end
  end

  defp wait_for_os_process_alive?(_os_pid, 0), do: true

  defp tmp_dir!(prefix) do
    Path.join(System.tmp_dir!(), "symphony-#{prefix}-#{System.unique_integer([:positive])}")
  end
end
