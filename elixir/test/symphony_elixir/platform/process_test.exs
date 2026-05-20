defmodule SymphonyElixir.Platform.ProcessTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @port_receive_timeout 5_000

  test "start_argv/2 resolves relative executables with cwd and env" do
    test_root = tmp_dir!("argv")

    on_exit(fn -> File.rm_rf(test_root) end)

    executable = Path.join(test_root, "print-context")

    File.write!(executable, """
    #!/bin/sh
    printf 'cwd=%s env=%s arg=%s\\n' "$PWD" "$SYMPHONY_PROCESS_TEST" "$1"
    """)

    File.chmod!(executable, 0o755)

    assert {:ok, port} =
             PlatformProcess.start_argv(["./print-context", "value"],
               cwd: test_root,
               env: %{"SYMPHONY_PROCESS_TEST" => "ok"},
               line: 1024
             )

    assert_receive {^port, {:data, {:eol, line}}}, @port_receive_timeout
    assert line in Enum.map(path_variants(test_root), &"cwd=#{&1} env=ok arg=value")
    assert_receive {^port, {:exit_status, 0}}, @port_receive_timeout

    assert :ok = PlatformProcess.close_port(port)
  end

  test "start_argv/2 returns command_not_found for missing executables" do
    test_root = tmp_dir!("missing")

    on_exit(fn -> File.rm_rf(test_root) end)

    assert {:error, {:command_not_found, "missing-symphony-process-test"}} =
             PlatformProcess.start_argv(["missing-symphony-process-test"], cwd: test_root)
  end

  test "start_argv/2 returns command_not_executable for non-executable paths" do
    test_root = tmp_dir!("not-executable")

    on_exit(fn -> File.rm_rf(test_root) end)

    executable = Path.join(test_root, "not-executable")
    File.write!(executable, "#!/bin/sh\nprintf nope\n")
    File.chmod!(executable, 0o644)

    assert {:error, {:command_not_executable, "./not-executable"}} =
             PlatformProcess.start_argv(["./not-executable"], cwd: test_root)
  end

  test "start_shell/2 returns invalid_cwd for missing working directories" do
    test_root = tmp_dir!("invalid-cwd")
    missing_cwd = Path.join(test_root, "missing")

    on_exit(fn -> File.rm_rf(test_root) end)

    assert {:error, {:invalid_cwd, ^missing_cwd}} =
             PlatformProcess.start_shell("printf unreachable", cwd: missing_cwd)
  end

  test "start_shell/2 starts a bash command in line mode" do
    test_root = tmp_dir!("shell")

    on_exit(fn -> File.rm_rf(test_root) end)

    assert {:ok, port} =
             PlatformProcess.start_shell("printf 'shell-ready:%s\\n' \"$PWD\"",
               cwd: test_root,
               line: 1024
             )

    assert_receive {^port, {:data, {:eol, line}}}, @port_receive_timeout
    assert line in Enum.map(path_variants(test_root), &"shell-ready:#{&1}")
    assert_receive {^port, {:exit_status, 0}}, @port_receive_timeout

    assert :ok = PlatformProcess.close_port(port)
  end

  test "close_port/1 is idempotent for closed ports" do
    test_root = tmp_dir!("close")

    on_exit(fn -> File.rm_rf(test_root) end)

    assert {:ok, port} = PlatformProcess.start_shell("while true; do sleep 1; done", cwd: test_root)
    os_pid = wait_for_port_os_pid!(port)

    assert :ok = PlatformProcess.close_port(port)
    assert :ok = PlatformProcess.close_port(port)

    PlatformProcess.terminate_os_process(os_pid, initial_signal?: false, grace_ms: 50, kill_wait_ms: 250)
  end

  test "terminate_os_process/2 escalates when a process ignores TERM" do
    test_root = tmp_dir!("terminate")

    on_exit(fn -> File.rm_rf(test_root) end)

    elixir = System.find_executable("elixir") || flunk("elixir executable is required for this test")

    assert {:ok, port} =
             PlatformProcess.start_argv(
               [
                 elixir,
                 "-e",
                 ":os.set_signal(:sigterm, :ignore); IO.puts(\"ready\"); Process.sleep(:infinity)"
               ],
               cwd: test_root,
               line: 1024
             )

    os_pid = wait_for_port_os_pid!(port)
    assert_receive {^port, {:data, {:eol, "ready"}}}, @port_receive_timeout
    assert PlatformProcess.os_process_alive?(os_pid)

    result =
      PlatformProcess.terminate_os_process(os_pid,
        grace_ms: 50,
        kill_wait_ms: 1_000,
        poll_ms: 25
      )

    assert :ok = PlatformProcess.close_port(port)
    assert result.os_pid == os_pid
    assert result.signals_sent == ["TERM", "KILL"]
    refute result.alive?
    refute PlatformProcess.os_process_alive?(os_pid)
  end

  test "terminate_os_process_tree/2 terminates descendants that outlive the parent" do
    test_root = tmp_dir!("terminate-tree")

    on_exit(fn -> File.rm_rf(test_root) end)

    executable = Path.join(test_root, "parent-with-child")
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
    assert PlatformProcess.os_process_alive?(parent_pid)
    assert PlatformProcess.os_process_alive?(child_pid)

    result =
      PlatformProcess.terminate_os_process_tree(parent_pid,
        process_group?: true,
        grace_ms: 50,
        kill_wait_ms: 1_000,
        poll_ms: 25
      )

    assert :ok = PlatformProcess.close_port(port)
    assert result.os_pid == parent_pid
    assert child_pid in result.descendant_pids
    refute result.alive?
    refute PlatformProcess.os_process_alive?(parent_pid)
    refute PlatformProcess.os_process_alive?(child_pid)
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

  defp path_variants(path) do
    expanded = Path.expand(path)

    if String.starts_with?(expanded, "/var/") do
      [expanded, "/private#{expanded}"]
    else
      [expanded]
    end
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-platform-process-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
