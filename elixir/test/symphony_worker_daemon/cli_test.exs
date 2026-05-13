defmodule SymphonyWorkerDaemon.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias SymphonyElixir.CLI, as: RootCLI
  alias SymphonyWorkerDaemon.CLI

  test "root CLI dispatches worker-daemon commands without main app guardrail parsing" do
    parent = self()

    deps = %{
      worker_daemon_evaluate: fn args ->
        send(parent, {:worker_daemon_args, args})
        :ok
      end
    }

    assert :ok = RootCLI.evaluate(["worker-daemon", "--workspace-root", "tmp/work"], deps)
    assert_received {:worker_daemon_args, ["--workspace-root", "tmp/work"]}
  end

  test "parses production daemon options and starts server with normalized config" do
    parent = self()
    root = Path.expand("tmp/worker-daemon-root")
    elixir = System.find_executable("elixir") || flunk("elixir executable is required")

    deps =
      deps(%{
        getenv: fn
          "DAEMON_TOKEN" -> "daemon-token"
          _name -> nil
        end,
        dir?: fn ^root -> true end,
        canonicalize: fn ^root -> {:ok, root} end,
        start_server: fn opts ->
          send(parent, {:server_opts, opts})
          {:ok, self()}
        end
      })

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.evaluate(
                   [
                     "--workspace-root",
                     root,
                     "--host",
                     "127.0.0.1",
                     "--port",
                     "4101",
                     "--token-env",
                     "DAEMON_TOKEN",
                     "--owner",
                     "control-plane-a",
                     "--tenant-id",
                     "tenant-a",
                     "--session-ledger-path",
                     "tmp/session-ledger.json",
                     "--worker-id",
                     "worker-a",
                     "--daemon-instance-id",
                     "daemon-a",
                     "--worker-profile-version",
                     "profile-v1",
                     "--max-sessions",
                     "3",
                     "--max-sessions-per-tenant",
                     "1",
                     "--rate-limit-window-ms",
                     "30000",
                     "--unauthenticated-rate-limit",
                     "20",
                     "--api-rate-limit",
                     "200",
                     "--session-create-rate-limit",
                     "10",
                     "--allow-executable",
                     elixir
                   ],
                   deps
                 )
      end)

    assert output =~ "Symphony worker daemon listening on http://127.0.0.1:4101"
    assert output =~ "worker_id=worker-a daemon_instance_id=daemon-a"
    assert_received {:server_opts, opts}
    assert Keyword.fetch!(opts, :ip) == {127, 0, 0, 1}
    assert Keyword.fetch!(opts, :port) == 4101
    assert Keyword.fetch!(opts, :token) == "daemon-token"
    assert Keyword.fetch!(opts, :owner) == "control-plane-a"
    assert Keyword.fetch!(opts, :tenant_id) == "tenant-a"
    assert Keyword.fetch!(opts, :session_ledger_path) == Path.expand("tmp/session-ledger.json")
    assert Keyword.fetch!(opts, :worker_profile_version) == "profile-v1"
    assert Keyword.fetch!(opts, :workspace_roots) == [root]
    assert Keyword.fetch!(opts, :max_sessions) == 3
    assert Keyword.fetch!(opts, :max_sessions_per_tenant) == 1
    assert Keyword.fetch!(opts, :rate_limit_window_ms) == 30_000
    assert Keyword.fetch!(opts, :unauthenticated_rate_limit) == 20
    assert Keyword.fetch!(opts, :api_rate_limit) == 200
    assert Keyword.fetch!(opts, :session_create_rate_limit) == 10
    assert [%{"path" => ^elixir}] = Keyword.fetch!(opts, :allowed_executables)
    refute Keyword.fetch!(opts, :allow_shell?)
    refute Keyword.fetch!(opts, :allow_any_executable?)
    refute Keyword.fetch!(opts, :allow_unauthenticated?)
    refute Keyword.fetch!(opts, :enable_dynamic_tool_bridge_proxy?)
    assert Keyword.fetch!(opts, :allowed_dynamic_tool_bridge_upstreams) == []
    refute Keyword.fetch!(opts, :allow_private_dynamic_tool_bridge_upstreams?)
  end

  test "requires a workspace root" do
    deps = deps()

    assert {:error, message} = CLI.evaluate(["--token", "daemon-token"], deps)
    assert message =~ "At least one --workspace-root is required"
  end

  test "requires authentication unless explicitly disabled for isolated development" do
    root = Path.expand("tmp/worker-daemon-root")
    deps = deps(%{dir?: fn ^root -> true end, canonicalize: fn ^root -> {:ok, root} end})

    assert {:error, message} = CLI.evaluate(["--workspace-root", root, "--allow-any-executable"], deps)
    assert message =~ "Worker daemon authentication token is required"

    output =
      capture_io(fn ->
        assert :ok = CLI.evaluate(["--workspace-root", root, "--allow-unauthenticated", "--allow-any-executable"], deps)
      end)

    assert output =~ "Symphony worker daemon listening"
  end

  test "requires executable policy unless isolated allow-any mode is explicit" do
    root = Path.expand("tmp/worker-daemon-root")
    deps = deps(%{dir?: fn ^root -> true end, canonicalize: fn ^root -> {:ok, root} end})

    assert {:error, message} = CLI.evaluate(["--workspace-root", root, "--token", "daemon-token"], deps)
    assert message =~ "At least one --allow-executable is required"

    output =
      capture_io(fn ->
        assert :ok = CLI.evaluate(["--workspace-root", root, "--token", "daemon-token", "--allow-any-executable"], deps)
      end)

    assert output =~ "Symphony worker daemon listening"
  end

  test "rejects invalid listen hosts before starting dependencies" do
    parent = self()

    deps =
      deps(%{
        ensure_dependencies: fn ->
          send(parent, :dependencies_started)
          :ok
        end
      })

    assert {:error, message} =
             CLI.evaluate(["--workspace-root", "tmp/work", "--token", "daemon-token", "--host", "not-a-valid-host"], deps)

    assert message =~ "Invalid worker daemon host"
    refute_received :dependencies_started
  end

  defp deps(overrides \\ %{}) do
    Map.merge(
      %{
        ensure_dependencies: fn -> :ok end,
        start_server: fn _opts -> {:ok, self()} end,
        dir?: fn _path -> true end,
        canonicalize: fn path -> {:ok, Path.expand(path)} end,
        getenv: fn _name -> nil end,
        hostname: fn -> {:ok, "worker-host"} end,
        uuid: fn -> "daemon-uuid" end
      },
      overrides
    )
  end
end
