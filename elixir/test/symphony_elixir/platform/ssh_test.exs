defmodule SymphonyElixir.Platform.SSHTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Platform.SSH

  test "run/3 keeps bracketed IPv6 host:port targets intact" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-ipv6-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file)

    assert {:ok, {"", 0}} =
             SSH.run("root@[::1]:2200", "printf ok", stderr_to_stdout: true)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-T -p 2200 root@[::1] bash -lc"
    assert trace =~ "printf ok"
  end

  test "run/3 rejects ambiguous unbracketed IPv6 host:port targets" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-ipv6-raw-test-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(test_root)

    assert {:error, :invalid_destination} =
             SSH.run("::1:2200", "printf ok", stderr_to_stdout: true)
  end

  test "run/3 passes host:port targets through ssh -p" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")
    previous_ssh_config = System.get_env("SYMPHONY_SSH_CONFIG")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMPHONY_SSH_CONFIG", previous_ssh_config)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file)
    System.put_env("SYMPHONY_SSH_CONFIG", "/tmp/symphony-test-ssh-config")

    assert {:ok, {"", 0}} =
             SSH.run("localhost:2222", "echo ready", stderr_to_stdout: true)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-F /tmp/symphony-test-ssh-config"
    assert trace =~ "-T -p 2222 localhost bash -lc"
    assert trace =~ "echo ready"
  end

  test "run/3 keeps the user prefix when parsing user@host:port targets" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-user-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file)

    assert {:ok, {"", 0}} =
             SSH.run("root@127.0.0.1:2200", "printf ok", stderr_to_stdout: true)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-T -p 2200 root@127.0.0.1 bash -lc"
    assert trace =~ "printf ok"
  end

  test "run/3 returns an error when ssh is unavailable" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-missing-test-#{System.unique_integer([:positive])}")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(test_root)
    System.put_env("PATH", test_root)

    assert {:error, :ssh_not_found} = SSH.run("localhost", "printf ok")
  end

  test "copy_dir/4 passes host:port targets through scp -P" do
    test_root = Path.join(System.tmp_dir!(), "symphony-scp-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "scp.trace")
    previous_path = System.get_env("PATH")
    previous_ssh_config = System.get_env("SYMPHONY_SSH_CONFIG")
    source_dir = Path.join(test_root, ".codex")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMPHONY_SSH_CONFIG", previous_ssh_config)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(source_dir)
    File.write!(Path.join(source_dir, "SKILL.md"), "# test\n")
    install_fake_scp!(test_root, trace_file)
    System.put_env("SYMPHONY_SSH_CONFIG", "/tmp/symphony-test-ssh-config")

    assert {:ok, {"", 0}} =
             SSH.copy_dir("localhost:2222", source_dir, "/remote/workspace", stderr_to_stdout: true)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-F /tmp/symphony-test-ssh-config"
    assert trace =~ "-P 2222"
    assert trace =~ source_dir
    assert trace =~ "localhost:/remote/workspace"
  end

  test "run/3 uses an explicit known-hosts source when configured" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-known-hosts-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")
    previous_known_hosts = System.get_env("SYMPHONY_SSH_KNOWN_HOSTS")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMPHONY_SSH_KNOWN_HOSTS", previous_known_hosts)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file)
    System.put_env("SYMPHONY_SSH_KNOWN_HOSTS", "/tmp/symphony-test-known-hosts")

    assert {:ok, {"", 0}} =
             SSH.run("localhost", "printf ok", stderr_to_stdout: true)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-o UserKnownHostsFile=/tmp/symphony-test-known-hosts"
  end

  test "copy_dir/4 returns an error when scp is unavailable" do
    test_root = Path.join(System.tmp_dir!(), "symphony-scp-missing-test-#{System.unique_integer([:positive])}")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    File.mkdir_p!(test_root)
    System.put_env("PATH", test_root)

    assert {:error, :scp_not_found} = SSH.copy_dir("localhost", "/tmp/source", "/tmp/dest")
  end

  test "start_port/3 supports binary output without line mode" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-port-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")
    previous_ssh_config = System.get_env("SYMPHONY_SSH_CONFIG")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMPHONY_SSH_CONFIG", previous_ssh_config)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file, """
    #!/bin/sh
    printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
    printf 'ready\\n'
    exit 0
    """)

    System.delete_env("SYMPHONY_SSH_CONFIG")

    assert {:ok, port} = SSH.start_port("localhost", "printf ok")
    assert is_port(port)
    wait_for_trace!(trace_file)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-T localhost bash -lc"
    refute trace =~ " -F "
  end

  test "start_port/3 supports line mode" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-line-port-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file, """
    #!/bin/sh
    printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
    printf 'ready\\n'
    exit 0
    """)

    assert {:ok, port} = SSH.start_port("localhost:2222", "printf ok", line: 256)
    assert is_port(port)
    wait_for_trace!(trace_file)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-T -p 2222 localhost bash -lc"
  end

  test "start_remote_port_forward/5 opens an SSH remote loopback forward" do
    test_root = Path.join(System.tmp_dir!(), "symphony-ssh-forward-test-#{System.unique_integer([:positive])}")
    trace_file = Path.join(test_root, "ssh.trace")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      File.rm_rf(test_root)
    end)

    install_fake_ssh!(test_root, trace_file, """
    #!/bin/sh
    printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
    sleep 30
    """)

    assert {:ok, port} = SSH.start_remote_port_forward("localhost:2222", 19_421, "127.0.0.1", 4521)
    assert is_port(port)
    wait_for_trace!(trace_file)

    trace = File.read!(trace_file)
    assert_common_ssh_options(trace)
    assert trace =~ "-o ExitOnForwardFailure=yes -N -T -p 2222"
    assert trace =~ "-R 127.0.0.1:19421:127.0.0.1:4521 localhost"

    Port.close(port)
  end

  test "start_remote_port_forward/5 validates forward ports before launching ssh" do
    assert {:error, :invalid_forward_port} =
             SSH.start_remote_port_forward("localhost", 0, "127.0.0.1", 4521)

    assert {:error, :invalid_forward_port} =
             SSH.start_remote_port_forward("localhost", 19_421, "127.0.0.1", 70_000)
  end

  test "remote_shell_command/1 escapes embedded single quotes" do
    assert SSH.remote_shell_command("printf 'hello'") ==
             "bash -lc 'printf '\"'\"'hello'\"'\"''"
  end

  test "normalize_host_entry/1 trims host strings and canonicalizes ports" do
    assert {:ok, "root@127.0.0.1:2200"} =
             SSH.normalize_host_entry("  root@127.0.0.1:02200  ")
  end

  test "normalize_host_entry/1 rejects blank and malformed single-colon targets" do
    assert {:error, :blank} = SSH.normalize_host_entry("   ")
    assert {:error, :invalid_port_target} = SSH.normalize_host_entry("localhost:http")
  end

  test "normalize_host_entry/1 rejects unsupported destination syntax" do
    assert {:error, :invalid_destination} = SSH.normalize_host_entry("ssh://worker-01")
    assert {:error, :invalid_destination} = SSH.normalize_host_entry("user@@worker-01")
    assert {:error, :invalid_destination} = SSH.normalize_host_entry("::1:2200")
  end

  defp install_fake_ssh!(test_root, trace_file, script \\ nil) do
    fake_bin_dir = Path.join(test_root, "bin")
    fake_ssh = Path.join(fake_bin_dir, "ssh")

    File.mkdir_p!(fake_bin_dir)

    File.write!(
      fake_ssh,
      script ||
        """
        #!/bin/sh
        printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
        exit 0
        """
    )

    File.chmod!(fake_ssh, 0o755)
    System.put_env("PATH", fake_bin_dir <> ":" <> (System.get_env("PATH") || ""))
  end

  defp install_fake_scp!(test_root, trace_file, script \\ nil) do
    fake_bin_dir = Path.join(test_root, "bin")
    fake_scp = Path.join(fake_bin_dir, "scp")

    File.mkdir_p!(fake_bin_dir)

    File.write!(
      fake_scp,
      script ||
        """
        #!/bin/sh
        printf 'ARGV:%s\\n' "$*" >> "#{trace_file}"
        exit 0
        """
    )

    File.chmod!(fake_scp, 0o755)
    System.put_env("PATH", fake_bin_dir <> ":" <> (System.get_env("PATH") || ""))
  end

  defp wait_for_trace!(trace_file, attempts \\ 80)
  defp wait_for_trace!(trace_file, 0), do: flunk("timed out waiting for fake ssh trace at #{trace_file}")

  defp wait_for_trace!(trace_file, attempts) do
    if File.exists?(trace_file) and File.read!(trace_file) != "" do
      :ok
    else
      Process.sleep(25)
      wait_for_trace!(trace_file, attempts - 1)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp assert_common_ssh_options(trace) do
    assert trace =~ "-o BatchMode=yes"
    assert trace =~ "-o NumberOfPasswordPrompts=0"
    assert trace =~ "-o KbdInteractiveAuthentication=no"
    assert trace =~ "-o StrictHostKeyChecking=yes"
  end
end
