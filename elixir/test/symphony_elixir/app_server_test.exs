defmodule SymphonyElixir.AgentProvider.Codex.AppServerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.AgentProvider.Codex.Tooling
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.CommandEnv

  defmodule FakeMcpDynamicToolSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(opts), do: Keyword.fetch!(opts, :dynamic_tool_source_context)
    def kind(_context), do: "fake_mcp"

    def tools(_context, _opts) do
      [
        %{
          "name" => "linear_issue_snapshot",
          "description" => "Read a Linear issue workflow snapshot.",
          "inputSchema" => %{
            "type" => "object",
            "required" => ["issue_id"],
            "properties" => %{"issue_id" => %{"type" => "string"}}
          },
          "capability" => "tracker.issue_snapshot",
          "sideEffect" => "read_only",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        }
      ]
    end

    def environment(_context, _opts), do: %{}

    def execute(%{owner: owner}, tool, arguments, opts) do
      send(owner, {:fake_mcp_dynamic_tool_called, tool, arguments, Keyword.get(opts, :workspace)})
      {:success, %{"tool" => tool, "arguments" => arguments}}
    end
  end

  test "stop_session terminates lingering local app-server processes" do
    bash = System.find_executable("bash") || flunk("bash executable is required for this test")
    kill_executable = System.find_executable("kill") || flunk("kill executable is required for this test")
    ps_executable = System.find_executable("ps") || flunk("ps executable is required for this test")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(bash)},
        [
          :binary,
          :stderr_to_stdout,
          args: [~c"-lc", ~c"trap '' HUP TERM; while :; do sleep 1; done"]
        ]
      )

    {:os_pid, os_pid} = :erlang.port_info(port, :os_pid)
    assert os_process_alive?(kill_executable, ps_executable, os_pid)

    log =
      capture_log(fn ->
        assert :ok = AppServer.stop_session(%{port: port})
      end)

    assert wait_for_os_process_exit(kill_executable, ps_executable, os_pid, 20, 50)
    assert log =~ "codex_session_process_termination_escalated"
    assert log =~ "signal=-TERM"
  end

  test "app server rejects the workspace root and paths outside workspace root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-cwd-guard-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      outside_workspace = Path.join(test_root, "outside")

      File.mkdir_p!(workspace_root)
      File.mkdir_p!(outside_workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root
      )

      issue = %Issue{
        id: "issue-workspace-guard",
        identifier: "MT-999",
        title: "Validate workspace guard",
        description: "Ensure app-server refuses invalid cwd targets",
        state: "In Progress",
        url: "https://example.org/issues/MT-999",
        labels: ["backend"]
      }

      assert {:error, {:invalid_workspace_cwd, :workspace_root, _path}} =
               AppServer.run(workspace_root, "guard", issue, codex_app_server_opts(workspace_root))

      assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, _path, _root}} =
               AppServer.run(outside_workspace, "guard", issue, codex_app_server_opts(outside_workspace))
    after
      File.rm_rf(test_root)
    end
  end

  test "app server rejects symlink escape cwd paths under the workspace root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-symlink-cwd-guard-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      outside_workspace = Path.join(test_root, "outside")
      symlink_workspace = Path.join(workspace_root, "MT-1000")

      File.mkdir_p!(workspace_root)
      File.mkdir_p!(outside_workspace)
      File.ln_s!(outside_workspace, symlink_workspace)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root
      )

      issue = %Issue{
        id: "issue-workspace-symlink-guard",
        identifier: "MT-1000",
        title: "Validate symlink workspace guard",
        description: "Ensure app-server refuses symlink escape cwd targets",
        state: "In Progress",
        url: "https://example.org/issues/MT-1000",
        labels: ["backend"]
      }

      assert {:error, {:invalid_workspace_cwd, :symlink_escape, ^symlink_workspace, _root}} =
               AppServer.run(symlink_workspace, "guard", issue, codex_app_server_opts(symlink_workspace))
    after
      File.rm_rf(test_root)
    end
  end

  test "app server passes explicit turn sandbox policies through unchanged" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-supported-turn-policies-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-1001")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-supported-turn-policies.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-supported-turn-policies.trace}"
      count=0

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-1001"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-1001"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      issue = %Issue{
        id: "issue-supported-turn-policies",
        identifier: "MT-1001",
        title: "Validate explicit turn sandbox policy passthrough",
        description: "Ensure runtime startup forwards configured turn sandbox policies unchanged",
        state: "In Progress",
        url: "https://example.org/issues/MT-1001",
        labels: ["backend"]
      }

      policy_cases = [
        %{"type" => "dangerFullAccess"},
        %{"type" => "externalSandbox", "profile" => "remote-ci"},
        %{"type" => "workspaceWrite", "writableRoots" => ["relative/path"], "networkAccess" => true},
        %{"type" => "futureSandbox", "nested" => %{"flag" => true}}
      ]

      Enum.each(policy_cases, fn configured_policy ->
        File.rm(trace_file)

        write_workflow_file!(Workflow.workflow_file_path(),
          workspace_root: workspace_root,
          agent_provider_options: %{
            command: "#{codex_binary} app-server",
            turn_sandbox_policy: configured_policy
          }
        )

        assert {:ok, _result} =
                 AppServer.run(
                   workspace,
                   "Validate supported turn policy",
                   issue,
                   codex_app_server_opts(workspace)
                 )

        trace = File.read!(trace_file)
        lines = String.split(trace, "\n", trim: true)

        assert Enum.any?(lines, fn line ->
                 if String.starts_with?(line, "JSON:") do
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()
                   |> then(fn payload ->
                     payload["method"] == "turn/start" &&
                       get_in(payload, ["params", "sandboxPolicy"]) == configured_policy
                   end)
                 else
                   false
                 end
               end)
      end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server prefers command_argv and preserves argv boundaries for local launch" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-command-argv-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-ARGV")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-command-argv.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEX_ARGV_TRACE")

      on_exit(fn ->
        restore_env("SYMP_TEST_CODEX_ARGV_TRACE", previous_trace)
      end)

      System.put_env("SYMP_TEST_CODEX_ARGV_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEX_ARGV_TRACE:-/tmp/codex-command-argv.trace}"
      count=0
      printf 'ARGC:%s\\n' "$#" >> "$trace_file"
      index=0
      for arg in "$@"; do
        index=$((index + 1))
        printf 'ARG:%s:%s\\n' "$index" "$arg" >> "$trace_file"
      done

      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-argv"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-argv"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{
          command: "missing-codex app-server",
          command_argv: [codex_binary, "app-server", "--model", "gpt 5"]
        }
      )

      issue = %Issue{
        id: "issue-command-argv",
        identifier: "MT-ARGV",
        title: "Validate command argv",
        description: "Ensure argv launch avoids shell splitting",
        state: "In Progress",
        url: "https://example.org/issues/MT-ARGV",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(workspace, "Validate command argv", issue, codex_app_server_opts(workspace))

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert "ARGC:3" in lines
      assert "ARG:1:app-server" in lines
      assert "ARG:2:--model" in lines
      assert "ARG:3:gpt 5" in lines
      refute Enum.any?(lines, &String.contains?(&1, "missing-codex"))
    after
      File.rm_rf(test_root)
    end
  end

  test "app server composes codex process env through the shared runtime environment path" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-env-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-ENV")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-env.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEX_ENV_TRACE")
      previous_linear_api_key = System.get_env("SYMPHONY_LINEAR_API_KEY")

      on_exit(fn ->
        restore_env("SYMP_TEST_CODEX_ENV_TRACE", previous_trace)
        restore_env("SYMPHONY_LINEAR_API_KEY", previous_linear_api_key)
      end)

      System.put_env("SYMP_TEST_CODEX_ENV_TRACE", trace_file)
      System.delete_env("SYMPHONY_LINEAR_API_KEY")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEX_ENV_TRACE:-/tmp/codex-env.trace}"
      count=0
      printf 'ENV_CODEX_MANAGED_TOKEN:%s\\n' "${CODEX_MANAGED_TOKEN:-}" >> "$trace_file"
      printf 'ENV_SYMPHONY_LINEAR_API_KEY:%s\\n' "${SYMPHONY_LINEAR_API_KEY:-}" >> "$trace_file"
      printf 'ENV_SYMPHONY_REPO_PROVIDER_REPOSITORY:%s\\n' "${SYMPHONY_REPO_PROVIDER_REPOSITORY:-}" >> "$trace_file"

      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-env"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-env"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command_argv: [codex_binary, "app-server"]},
        repo_provider_repository: "acme/widgets"
      )

      issue = %Issue{
        id: "issue-env",
        identifier: "MT-ENV",
        title: "Validate codex env composition",
        description: "Ensure managed material reaches the provider process without dynamic source secrets",
        state: "In Progress",
        url: "https://example.org/issues/MT-ENV",
        labels: ["backend"]
      }

      material =
        SymphonyElixir.Agent.Credential.Material.new(env: %{"CODEX_MANAGED_TOKEN" => "managed-secret"})

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Validate env",
                 issue,
                 codex_app_server_opts(workspace, agent_credential_material: material)
               )

      lines = File.read!(trace_file) |> String.split("\n", trim: true)

      assert "ENV_CODEX_MANAGED_TOKEN:managed-secret" in lines
      assert "ENV_SYMPHONY_LINEAR_API_KEY:" in lines
      assert "ENV_SYMPHONY_REPO_PROVIDER_REPOSITORY:acme/widgets" in lines
    after
      File.rm_rf(test_root)
    end
  end

  test "app server marks request-for-input events as a hard failure" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-input-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-88")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-input.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-input.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-88\"}}}'
            ;;
          3)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-88\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"method\":\"turn/input_required\",\"id\":\"resp-1\",\"params\":{\"requiresInput\":true,\"reason\":\"blocked\"}}'
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-input",
        identifier: "MT-88",
        title: "Input needed",
        description: "Cannot satisfy codex input",
        state: "In Progress",
        url: "https://example.org/issues/MT-88",
        labels: ["backend"]
      }

      assert {:error, {:turn_input_required, payload}} =
               AppServer.run(workspace, "Needs input", issue, codex_app_server_opts(workspace))

      assert payload["method"] == "turn/input_required"
    after
      File.rm_rf(test_root)
    end
  end

  test "app server fails when command execution approval is required under safer defaults" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-approval-required-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-89")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-89"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-89"}}}'
            printf '%s\\n' '{"id":99,"method":"item/commandExecution/requestApproval","params":{"command":"gh pr view","cwd":"/tmp","reason":"need approval"}}'
            ;;
          *)
            sleep 1
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-approval-required",
        identifier: "MT-89",
        title: "Approval required",
        description: "Ensure safer defaults do not auto approve requests",
        state: "In Progress",
        url: "https://example.org/issues/MT-89",
        labels: ["backend"]
      }

      assert {:error, {:approval_required, payload}} =
               AppServer.run(workspace, "Handle approval request", issue, codex_app_server_opts(workspace))

      assert payload["method"] == "item/commandExecution/requestApproval"
    after
      File.rm_rf(test_root)
    end
  end

  test "app server auto-approves command execution approval requests when approval policy is never" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-auto-approve-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-89")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-auto-approve.trace")
      previous_trace = System.get_env("SYMP_TEST_CODex_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODex_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODex_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODex_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODex_TRACE:-/tmp/codex-auto-approve.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-89\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-89\"}}}'
            printf '%s\\n' '{\"id\":99,\"method\":\"item/commandExecution/requestApproval\",\"params\":{\"command\":\"gh pr view\",\"cwd\":\"/tmp\",\"reason\":\"need approval\"}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server", approval_policy: "never"}
      )

      issue = %Issue{
        id: "issue-auto-approve",
        identifier: "MT-89",
        title: "Auto approve request",
        description: "Ensure app-server approval requests are handled automatically",
        state: "In Progress",
        url: "https://example.org/issues/MT-89",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(workspace, "Handle approval request", issue, codex_app_server_opts(workspace))

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 1 and
                   get_in(payload, ["params", "capabilities", "experimentalApi"]) == true
               else
                 false
               end
             end)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 2 and not Map.has_key?(payload["params"], "dynamicTools")
               else
                 false
               end
             end)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 99 and get_in(payload, ["result", "decision"]) == "acceptForSession"
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server exposes planned dynamic tools through the Codex MCP bridge" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-codex-mcp-tools-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-MCP")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-mcp-tools.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEX_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEX_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEX_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEX_TRACE", trace_file)
      File.mkdir_p!(Path.join(workspace, ".git"))

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEX_TRACE:-/tmp/codex-mcp-tools.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"
      printf 'BRIDGE_BASE:%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL" >> "$trace_file"
      printf 'BRIDGE_TRANSPORT:%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT" >> "$trace_file"
      printf 'BRIDGE_TOKEN:%s\\n' "$SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN" >> "$trace_file"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-mcp"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-mcp"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server", approval_policy: "never"}
      )

      issue = %Issue{
        id: "issue-codex-mcp-tools",
        identifier: "MT-MCP",
        title: "Codex MCP tools",
        description: "Ensure Codex receives planned dynamic tools through MCP",
        state: "In Progress",
        url: "https://example.org/issues/MT-MCP",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Use planned dynamic tools",
                 issue,
                 codex_app_server_opts(workspace,
                   http_port: 4521,
                   tool_context: codex_dynamic_tool_context_for_test()
                 )
               )

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, &String.contains?(&1, "mcp_servers={}"))
      assert Enum.any?(lines, &String.contains?(&1, "mcp_servers.symphony-planned-tools.command=\"sh\""))
      assert Enum.any?(lines, &String.contains?(&1, "mcp_servers.symphony-planned-tools.args=[\".symphony/codex/planned_tools_mcp.sh\"]"))
      assert Enum.any?(lines, &(&1 == "BRIDGE_BASE:http://127.0.0.1:4521/api/v1/agent-tools/dynamic"))
      assert Enum.any?(lines, &(&1 == "BRIDGE_TRANSPORT:local_http"))
      assert Enum.any?(lines, &String.match?(&1, ~r/^BRIDGE_TOKEN:.+/))

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "thread/start" and not Map.has_key?(payload["params"], "dynamicTools")
                 end)
               else
                 false
               end
             end)

      server_source = File.read!(Path.join([workspace, ".symphony", "codex", "planned_tools_mcp.js"]))
      assert server_source =~ "linear_issue_snapshot"
      refute server_source =~ "linear_graphql"

      wrapper_source = File.read!(Path.join([workspace, ".symphony", "codex", "planned_tools_mcp.sh"]))
      assert wrapper_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL='http://127.0.0.1:4521/api/v1/agent-tools/dynamic'"
      assert wrapper_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT='local_http'"
      assert wrapper_source =~ "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN='"
      assert wrapper_source =~ "exec node \"$script_dir/planned_tools_mcp.js\""

      assert File.read!(Path.join([workspace, ".git", "info", "exclude"])) =~ ".symphony/\n"
    after
      File.rm_rf(test_root)
    end
  end

  test "generated Codex MCP bridge executes planned dynamic tools through the runtime bridge" do
    System.find_executable("node") || flunk("node executable is required for this test")

    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-codex-mcp-wrapper-#{System.unique_integer([:positive])}"
      )

    bridge_port = free_port!()

    try do
      workspace = Path.join(test_root, "workspaces/MT-MCP-WRAPPER")
      File.mkdir_p!(Path.join(workspace, ".git"))
      EventStore.reset()

      start_supervised!({SymphonyElixir.HttpServer, [host: "127.0.0.1", port: bridge_port]})
      assert wait_until(fn -> SymphonyElixir.HttpServer.bound_port() == bridge_port end)

      tool_context =
        DynamicTool.capture_context(
          dynamic_tool_source: FakeMcpDynamicToolSource,
          dynamic_tool_source_context: %{owner: self()}
        )

      assert {:ok, runtime} =
               DynamicToolBridge.start(
                 http_port: bridge_port,
                 tool_context: tool_context,
                 run_id: "run-mcp-wrapper",
                 issue_id: "issue-mcp-wrapper",
                 issue_identifier: "MT-MCP-WRAPPER",
                 agent_provider_kind: "codex"
               )

      try do
        assert :ok =
                 Tooling.write_runtime_mcp_server(workspace,
                   tool_context: tool_context,
                   dynamic_tool_bridge_runtime: runtime
                 )

        mcp = start_mcp_wrapper!(workspace)

        try do
          assert %{
                   "result" => %{
                     "capabilities" => %{"tools" => %{}},
                     "serverInfo" => %{"name" => "symphony-planned-tools"}
                   }
                 } =
                   mcp_request!(mcp, 1, "initialize", %{
                     "protocolVersion" => "2024-11-05",
                     "capabilities" => %{},
                     "clientInfo" => %{"name" => "symphony-test", "version" => "0.0.0"}
                   })

          assert %{"result" => %{"tools" => tools}} = mcp_request!(mcp, 2, "tools/list", %{})
          assert Enum.any?(tools, &(&1["name"] == "linear_issue_snapshot"))

          assert %{"result" => %{"isError" => false, "content" => [%{"type" => "text", "text" => text}]}} =
                   mcp_request!(mcp, 3, "tools/call", %{
                     "name" => "linear_issue_snapshot",
                     "arguments" => %{"issue_id" => "MT-MCP-WRAPPER"}
                   })

          assert Jason.decode!(text) == %{
                   "tool" => "linear_issue_snapshot",
                   "arguments" => %{"issue_id" => "MT-MCP-WRAPPER"}
                 }

          assert_receive {:fake_mcp_dynamic_tool_called, "linear_issue_snapshot", %{"issue_id" => "MT-MCP-WRAPPER"}, called_workspace}

          assert normalized_path(called_workspace) == normalized_path(workspace)

          event =
            EventStore.recent_issue_events(%{run_id: "run-mcp-wrapper"}, limit: 10)
            |> Enum.find(&(&1["event"] == "tool_call_succeeded" and &1["tool_name"] == "linear_issue_snapshot"))

          assert event["issue_id"] == "issue-mcp-wrapper"
          assert event["issue_identifier"] == "MT-MCP-WRAPPER"
          assert event["agent_provider_kind"] == "codex"
          assert event["dynamic_tool_usage_kind"] == "typed"
        after
          close_mcp_wrapper(mcp)
        end
      after
        DynamicToolBridge.stop(runtime)
      end
    after
      File.rm_rf(test_root)
    end
  end

  test "app server auto-approves MCP tool approval prompts when approval policy is never" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-tool-user-input-auto-approve-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-717")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-tool-user-input-auto-approve.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-tool-user-input-auto-approve.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-717\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-717\"}}}'
            printf '%s\\n' '{\"id\":110,\"method\":\"item/tool/requestUserInput\",\"params\":{\"itemId\":\"call-717\",\"questions\":[{\"header\":\"Approve app tool call?\",\"id\":\"mcp_tool_call_approval_call-717\",\"isOther\":false,\"isSecret\":false,\"options\":[{\"description\":\"Run the tool and continue.\",\"label\":\"Approve Once\"},{\"description\":\"Run the tool and remember this choice for this session.\",\"label\":\"Approve this Session\"},{\"description\":\"Decline this tool call and continue.\",\"label\":\"Deny\"},{\"description\":\"Cancel this tool call\",\"label\":\"Cancel\"}],\"question\":\"The linear MCP server wants to run the tool \\\"Save issue\\\", which may modify or delete data. Allow this action?\"}],\"threadId\":\"thread-717\",\"turnId\":\"turn-717\"}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server", approval_policy: "never"}
      )

      issue = %Issue{
        id: "issue-tool-user-input-auto-approve",
        identifier: "MT-717",
        title: "Auto approve MCP tool request user input",
        description: "Ensure app tool approval prompts continue automatically",
        state: "In Progress",
        url: "https://example.org/issues/MT-717",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(workspace, "Handle tool approval prompt", issue, codex_app_server_opts(workspace))

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 110 and
                   get_in(payload, ["result", "answers", "mcp_tool_call_approval_call-717", "answers"]) ==
                     ["Approve this Session"]
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server auto-approves MCP server elicitation approval prompts when approval policy is never" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-mcp-elicitation-auto-approve-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-720")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-mcp-elicitation-auto-approve.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEX_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEX_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEX_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEX_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEX_TRACE:-/tmp/codex-mcp-elicitation-auto-approve.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-720"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-720"}}}'
            printf '%s\\n' '{"id":120,"method":"mcpServer/elicitation/request","params":{"message":"Allow Symphony planned tools to call linear_issue_snapshot?","_meta":{"codex_approval_kind":"mcp_tool_call","codex_request_type":"approval_request","persist":["session","always"],"tool_name":"linear_issue_snapshot","tool_title":"Read Linear issue"}}}'
            ;;
          5)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server", approval_policy: "never"}
      )

      issue = %Issue{
        id: "issue-mcp-elicitation-auto-approve",
        identifier: "MT-720",
        title: "Auto approve MCP elicitation",
        description: "Ensure MCP server elicitation approvals continue automatically",
        state: "In Progress",
        url: "https://example.org/issues/MT-720",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(workspace, "Handle MCP elicitation approval prompt", issue, codex_app_server_opts(workspace))

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 120 and get_in(payload, ["result", "action"]) == "accept"
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server sends a generic non-interactive answer for freeform tool input prompts" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-tool-user-input-required-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-718")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-718"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-718"}}}'
            printf '%s\\n' '{"id":111,"method":"item/tool/requestUserInput","params":{"itemId":"call-718","questions":[{"header":"Provide context","id":"freeform-718","isOther":false,"isSecret":false,"options":null,"question":"What comment should I post back to the issue?"}],"threadId":"thread-718","turnId":"turn-718"}}'
            ;;
          5)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server", approval_policy: "never"}
      )

      issue = %Issue{
        id: "issue-tool-user-input-required",
        identifier: "MT-718",
        title: "Non interactive tool input answer",
        description: "Ensure arbitrary tool prompts receive a generic answer",
        state: "In Progress",
        url: "https://example.org/issues/MT-718",
        labels: ["backend"]
      }

      on_message = fn message -> send(self(), {:app_server_message, message}) end

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Handle generic tool input",
                 issue,
                 codex_app_server_opts(workspace, on_message: on_message)
               )

      assert_received {:app_server_message,
                       %{
                         event: :tool_input_auto_answered,
                         answer: "This is a non-interactive session. Operator input is unavailable."
                       }}
    after
      File.rm_rf(test_root)
    end
  end

  test "app server sends a generic non-interactive answer for option-based tool input prompts" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-tool-user-input-options-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-719")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-tool-user-input-options.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-tool-user-input-options.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-719\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-719\"}}}'
            printf '%s\\n' '{\"id\":112,\"method\":\"item/tool/requestUserInput\",\"params\":{\"itemId\":\"call-719\",\"questions\":[{\"header\":\"Choose an action\",\"id\":\"options-719\",\"isOther\":false,\"isSecret\":false,\"options\":[{\"description\":\"Use the default behavior.\",\"label\":\"Use default\"},{\"description\":\"Skip this step.\",\"label\":\"Skip\"}],\"question\":\"How should I proceed?\"}],\"threadId\":\"thread-719\",\"turnId\":\"turn-719\"}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-tool-user-input-options",
        identifier: "MT-719",
        title: "Option based tool input answer",
        description: "Ensure option prompts receive a generic non-interactive answer",
        state: "In Progress",
        url: "https://example.org/issues/MT-719",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Handle option based tool input",
                 issue,
                 codex_app_server_opts(workspace)
               )

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 112 and
                   get_in(payload, ["result", "answers", "options-719", "answers"]) == [
                     "This is a non-interactive session. Operator input is unavailable."
                   ]
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server rejects unsupported dynamic tool calls without stalling" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-tool-call-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-90")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-tool-call.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-tool-call.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-90\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-90\"}}}'
            printf '%s\\n' '{\"id\":101,\"method\":\"item/tool/call\",\"params\":{\"tool\":\"some_tool\",\"callId\":\"call-90\",\"threadId\":\"thread-90\",\"turnId\":\"turn-90\",\"arguments\":{}}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-tool-call",
        identifier: "MT-90",
        title: "Unsupported tool call",
        description: "Ensure unsupported tool calls do not stall a turn",
        state: "In Progress",
        url: "https://example.org/issues/MT-90",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(workspace, "Reject unsupported tool calls", issue, codex_app_server_opts(workspace))

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 101 and
                   get_in(payload, ["result", "success"]) == false and
                   String.contains?(
                     get_in(payload, ["result", "output"]),
                     "unsupported_app_server_tool_call"
                   )
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server rejects app-server tool callbacks even when the tool name is known" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-supported-tool-call-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-90A")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-supported-tool-call.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-supported-tool-call.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-90a\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-90a\"}}}'
            printf '%s\\n' '{\"id\":102,\"method\":\"item/tool/call\",\"params\":{\"name\":\"linear_provider_diagnostics\",\"callId\":\"call-90a\",\"threadId\":\"thread-90a\",\"turnId\":\"turn-90a\",\"arguments\":{}}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-supported-tool-call",
        identifier: "MT-90A",
        title: "Unsupported app-server tool callback",
        description: "Ensure app-server tool callbacks cannot execute dynamic tools",
        state: "In Progress",
        url: "https://example.org/issues/MT-90A",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Reject app-server tool callbacks",
                 issue,
                 codex_app_server_opts(workspace)
               )

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 payload =
                   line
                   |> String.trim_leading("JSON:")
                   |> Jason.decode!()

                 payload["id"] == 102 and
                   get_in(payload, ["result", "success"]) == false and
                   get_in(payload, ["result", "output"]) =~ "unsupported_app_server_tool_call" and
                   get_in(payload, ["result", "output"]) =~ "linear_provider_diagnostics"
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server emits unsupported_tool_call for app-server tool callbacks" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-tool-call-failed-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-90B")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "codex-tool-call-failed.trace")
      previous_trace = System.get_env("SYMP_TEST_CODEx_TRACE")

      on_exit(fn ->
        if is_binary(previous_trace) do
          System.put_env("SYMP_TEST_CODEx_TRACE", previous_trace)
        else
          System.delete_env("SYMP_TEST_CODEx_TRACE")
        end
      end)

      System.put_env("SYMP_TEST_CODEx_TRACE", trace_file)
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file="${SYMP_TEST_CODEx_TRACE:-/tmp/codex-tool-call-failed.trace}"
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' \"$line\" >> \"$trace_file\"

        case \"$count\" in
          1)
            printf '%s\\n' '{\"id\":1,\"result\":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{\"id\":2,\"result\":{\"thread\":{\"id\":\"thread-90b\"}}}'
            ;;
          4)
            printf '%s\\n' '{\"id\":3,\"result\":{\"turn\":{\"id\":\"turn-90b\"}}}'
            printf '%s\\n' '{\"id\":103,\"method\":\"item/tool/call\",\"params\":{\"tool\":\"linear_provider_diagnostics\",\"callId\":\"call-90b\",\"threadId\":\"thread-90b\",\"turnId\":\"turn-90b\",\"arguments\":{}}}'
            ;;
          5)
            printf '%s\\n' '{\"method\":\"turn/completed\"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-tool-call-failed",
        identifier: "MT-90B",
        title: "Unsupported app-server tool callback",
        description: "Ensure app-server tool callbacks emit a distinct event",
        state: "In Progress",
        url: "https://example.org/issues/MT-90B",
        labels: ["backend"]
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:app_server_message, message}) end

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Handle failed tool calls",
                 issue,
                 codex_app_server_opts(workspace,
                   on_message: on_message
                 )
               )

      assert_received {:app_server_message,
                       %{
                         event: :unsupported_tool_call,
                         payload: %{"params" => %{"tool" => "linear_provider_diagnostics"}},
                         tool_result: %{"success" => false, "output" => output}
                       }}

      assert output =~ "unsupported_app_server_tool_call"
    after
      File.rm_rf(test_root)
    end
  end

  test "app server buffers partial JSON lines until newline terminator" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-partial-line-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-91")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))

        case "$count" in
          1)
            padding=$(printf '%*s' 1100000 '' | tr ' ' a)
            printf '{"id":1,"result":{},"padding":"%s"}\\n' "$padding"
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-91"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-91"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-partial-line",
        identifier: "MT-91",
        title: "Partial line decode",
        description: "Ensure JSON parsing waits for newline-delimited messages",
        state: "In Progress",
        url: "https://example.org/issues/MT-91",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Validate newline-delimited buffering",
                 issue,
                 codex_app_server_opts(workspace)
               )
    after
      File.rm_rf(test_root)
    end
  end

  test "app server returns stall timeout when a turn stops producing events" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-stall-timeout-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-91S")
      codex_binary = Path.join(test_root, "fake-codex")
      trace_file = Path.join(test_root, "fake-codex.trace")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      trace_file=#{inspect(trace_file)}
      count=0
      while IFS= read -r line; do
        count=$((count + 1))
        printf '%s:%s\\n' "$count" "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-91s"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-91s"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"mcpServer/startupStatus/updated","params":{"error":null,"name":"symphony-planned-tools","status":"ready"}}'
            while :; do sleep 1; done
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{
          command: "#{codex_binary} app-server",
          approval_policy: "never",
          read_timeout_ms: 5_000,
          turn_timeout_ms: 30_000,
          stall_timeout_ms: 100
        }
      )

      issue = %Issue{
        id: "issue-stall-timeout",
        identifier: "MT-91S",
        title: "Stall timeout",
        description: "Ensure idle turns fail through stall timeout",
        state: "In Progress",
        url: "https://example.org/issues/MT-91S",
        labels: ["backend"]
      }

      started_at_ms = System.monotonic_time(:millisecond)

      result =
        AppServer.run(
          workspace,
          "Wait for a stalled turn",
          issue,
          codex_app_server_opts(workspace)
        )

      assert result == {:error, :stall_timeout}, "trace=#{File.read!(trace_file)}"

      assert System.monotonic_time(:millisecond) - started_at_ms < 10_000
    after
      File.rm_rf(test_root)
    end
  end

  test "app server captures codex side output and logs it through Logger" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-stderr-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-92")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-92"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-92"}}}'
            ;;
          4)
            printf '%s\\n' 'warning: this is stderr noise' >&2
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-stderr",
        identifier: "MT-92",
        title: "Capture stderr",
        description: "Ensure codex stderr is captured and logged",
        state: "In Progress",
        url: "https://example.org/issues/MT-92",
        labels: ["backend"]
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:app_server_message, message}) end

      log =
        capture_log(fn ->
          assert {:ok, _result} =
                   AppServer.run(
                     workspace,
                     "Capture stderr log",
                     issue,
                     codex_app_server_opts(workspace, on_message: on_message)
                   )
        end)

      assert_received {:app_server_message, %{event: :stream_warning, payload: "warning: this is stderr noise"}}
      assert_received {:app_server_message, %{event: :turn_completed}}
      refute_received {:app_server_message, %{event: :malformed}}
      assert log =~ "codex_session_started"
      assert log =~ "codex_turn_started"
      assert log =~ "codex_stream_warning"
      assert log =~ "codex_turn_completed"
      assert log =~ "codex_session_completed"
      assert log =~ ~s(payload_summary="warning: this is stderr noise")
    after
      File.rm_rf(test_root)
    end
  end

  test "app server emits malformed events for JSON-like protocol lines that fail to decode" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-malformed-protocol-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-93")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-93"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-93"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-malformed-protocol",
        identifier: "MT-93",
        title: "Malformed protocol frame",
        description: "Ensure malformed JSON-like frames are surfaced to the orchestrator",
        state: "In Progress",
        url: "https://example.org/issues/MT-93",
        labels: ["backend"]
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:app_server_message, message}) end

      log =
        capture_log(fn ->
          assert {:ok, _result} =
                   AppServer.run(
                     workspace,
                     "Capture malformed protocol line",
                     issue,
                     codex_app_server_opts(workspace, on_message: on_message)
                   )
        end)

      assert_received {:app_server_message, %{event: :malformed, payload: "{\"method\":\"turn/completed\""}}
      assert_received {:app_server_message, %{event: :turn_completed}}
      assert log =~ "codex_stream_malformed"
    after
      File.rm_rf(test_root)
    end
  end

  test "app server emits stream output events for non-warning side output" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-stream-output-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-94A")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-94a"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-94a"}}}'
            ;;
          4)
            printf '%s\\n' 'syncing workpad mirror'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-stream-output",
        identifier: "MT-94A",
        title: "Capture stream output",
        description: "Ensure plain non-JSON side output is surfaced to the orchestrator",
        state: "In Progress",
        url: "https://example.org/issues/MT-94A",
        labels: ["backend"]
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:app_server_message, message}) end

      assert {:ok, _result} =
               AppServer.run(
                 workspace,
                 "Capture stream output",
                 issue,
                 codex_app_server_opts(workspace, on_message: on_message)
               )

      assert_received {:app_server_message, %{event: :stream_output, payload: "syncing workpad mirror"}}

      assert_received {:app_server_message, %{event: :turn_completed}}
      refute_received {:app_server_message, %{event: :malformed}}
    after
      File.rm_rf(test_root)
    end
  end

  test "app server treats codex error notifications as turn failures" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-codex-error-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-94")
      codex_binary = Path.join(test_root, "fake-codex")
      File.mkdir_p!(workspace)

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      while IFS= read -r line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-94"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-94"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"error","params":{"message":"rate limit exhausted","code":"rate_limited"}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        agent_provider_options: %{command: "#{codex_binary} app-server"}
      )

      issue = %Issue{
        id: "issue-codex-error",
        identifier: "MT-94",
        title: "Codex error notification",
        description: "Ensure codex error notifications fail the turn",
        state: "In Progress",
        url: "https://example.org/issues/MT-94",
        labels: ["backend"]
      }

      test_pid = self()
      on_message = fn message -> send(test_pid, {:app_server_message, message}) end

      log =
        capture_log(fn ->
          assert {:error, {:codex_error, %{"code" => "rate_limited", "message" => "rate limit exhausted"}}} =
                   AppServer.run(
                     workspace,
                     "Handle codex error",
                     issue,
                     codex_app_server_opts(workspace, on_message: on_message)
                   )
        end)

      assert_received {:app_server_message, %{event: :codex_error}}
      refute_received {:app_server_message, %{event: :turn_completed}}
      assert log =~ "codex_turn_failed"
      assert log =~ "codex_session_failed"
      refute log =~ "codex_session_completed"
    after
      File.rm_rf(test_root)
    end
  end

  test "app server launches over ssh for remote workers" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-remote-ssh-#{System.unique_integer([:positive])}"
      )

    previous_path = System.get_env("PATH")
    previous_trace = System.get_env("SYMP_TEST_SSH_TRACE")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMP_TEST_SSH_TRACE", previous_trace)
    end)

    try do
      trace_file = Path.join(test_root, "ssh.trace")
      fake_ssh = Path.join(test_root, "ssh")
      remote_workspace = "/remote/workspaces/MT-REMOTE"

      File.mkdir_p!(test_root)
      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      count=0
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      case "$*" in
        *"__SYMPHONY_WORKSPACE_MISSING__"*)
          printf '%s\\n' '__SYMPHONY_WORKSPACE__\t0\t/remote/workspaces\t#{remote_workspace}'
          exit 0
          ;;
      esac

      while IFS= read -r line; do
        count=$((count + 1))
        printf 'JSON:%s\\n' "$line" >> "$trace_file"

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-remote"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-remote"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "/remote/workspaces",
        agent_provider_options: %{command: "fake-remote-codex app-server"},
        repo_provider_repository: "acme/widgets",
        repo_provider_api_base_url: "https://api.github.example.test",
        repo_provider_web_base_url: "https://github.example.test"
      )

      issue = %Issue{
        id: "issue-remote",
        identifier: "MT-REMOTE",
        title: "Run remote app server",
        description: "Validate ssh-backed codex startup",
        state: "In Progress",
        url: "https://example.org/issues/MT-REMOTE",
        labels: ["backend"]
      }

      assert {:ok, _result} =
               AppServer.run(
                 remote_workspace,
                 "Run remote worker",
                 issue,
                 codex_app_server_opts(remote_workspace, worker_host: "worker-01:2200")
               )

      trace = File.read!(trace_file)
      lines = String.split(trace, "\n", trim: true)

      assert argv_line =
               Enum.find(lines, fn line ->
                 String.starts_with?(line, "ARGV:") and String.contains?(line, "fake-remote-codex app-server")
               end)

      assert argv_line =~
               "-o BatchMode=yes -o NumberOfPasswordPrompts=0 -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -T -p 2200 worker-01 bash -lc"

      assert argv_line =~ "export SYMPHONY_REPO_PROVIDER_KIND="
      assert argv_line =~ "github"
      assert argv_line =~ "export SYMPHONY_REPO_PROVIDER_REPOSITORY="
      assert argv_line =~ "acme/widgets"
      assert argv_line =~ "export SYMPHONY_REPO_PROVIDER_API_BASE_URL="
      assert argv_line =~ "api.github.example.test"
      assert argv_line =~ "export SYMPHONY_REPO_PROVIDER_WEB_BASE_URL="
      assert argv_line =~ "github.example.test"
      assert argv_line =~ "cd "
      assert argv_line =~ remote_workspace
      assert argv_line =~ "exec "
      assert argv_line =~ "fake-remote-codex app-server"

      expected_turn_policy = %{
        "type" => "workspaceWrite",
        "writableRoots" => [remote_workspace],
        "readOnlyAccess" => %{"type" => "fullAccess"},
        "networkAccess" => false,
        "excludeTmpdirEnvVar" => false,
        "excludeSlashTmp" => false
      }

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "thread/start" &&
                     get_in(payload, ["params", "cwd"]) == remote_workspace
                 end)
               else
                 false
               end
             end)

      assert Enum.any?(lines, fn line ->
               if String.starts_with?(line, "JSON:") do
                 line
                 |> String.trim_leading("JSON:")
                 |> Jason.decode!()
                 |> then(fn payload ->
                   payload["method"] == "turn/start" &&
                     get_in(payload, ["params", "cwd"]) == remote_workspace &&
                     get_in(payload, ["params", "sandboxPolicy"]) == expected_turn_policy
                 end)
               else
                 false
               end
             end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server embeds Codex credential file materialization in ssh launch command" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-remote-credential-#{System.unique_integer([:positive])}"
      )

    previous_path = System.get_env("PATH")
    previous_trace = System.get_env("SYMP_TEST_SSH_TRACE")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMP_TEST_SSH_TRACE", previous_trace)
    end)

    try do
      trace_file = Path.join(test_root, "ssh.trace")
      fake_ssh = Path.join(test_root, "ssh")
      remote_workspace = "/remote/workspaces/MT-CODEX-CRED"
      codex_home = "/tmp/symphony-codex-test/codex-run"

      File.mkdir_p!(test_root)
      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      count=0
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"

      case "$*" in
        *"__SYMPHONY_WORKSPACE_MISSING__"*)
          printf '%s\\n' '__SYMPHONY_WORKSPACE__\t0\t/remote/workspaces\t#{remote_workspace}'
          exit 0
          ;;
      esac

      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-credential"}}}'
            ;;
          3)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-credential"}}}'
            ;;
          4)
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: "/remote/workspaces",
        agent_provider_options: %{command: "fake-remote-codex app-server"}
      )

      material =
        SymphonyElixir.Agent.Credential.Material.new(
          env: %{"CODEX_HOME" => codex_home},
          auth_metadata: %{
            "codex" => %{
              "credential_kind" => "codex_api_key",
              "codex_home" => codex_home,
              "api_key" => "sk-codex-remote-app-server"
            }
          }
        )

      issue = %Issue{
        id: "issue-codex-credential",
        identifier: "MT-CODEX-CRED",
        title: "Run remote app server with managed Codex auth",
        description: "Validate ssh-backed Codex credential materialization",
        state: "In Progress"
      }

      assert {:ok, _result} =
               AppServer.run(
                 remote_workspace,
                 "Run remote worker",
                 issue,
                 codex_app_server_opts(remote_workspace,
                   worker_host: "worker-01:2200",
                   agent_credential_material: material
                 )
               )

      trace = File.read!(trace_file)

      assert trace =~ "cli_auth_credentials_store"
      assert trace =~ "auth.json"
      assert trace =~ "export CODEX_HOME="
      assert trace =~ "trap "
      assert trace =~ codex_home
      assert trace =~ "fake-remote-codex app-server"
      refute trace =~ "export OPENAI_API_KEY="
    after
      File.rm_rf(test_root)
    end
  end

  test "worker daemon app server cleans remote managed Codex auth on stop" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-worker-daemon-credential-#{System.unique_integer([:positive])}"
      )

    try do
      sh = System.find_executable("sh") || flunk("sh executable is required for this test")
      workspace_root = Path.join(test_root, "workspaces")
      workspace = Path.join(workspace_root, "MT-CODEX-WD-CRED")
      fake_codex = Path.join(test_root, "fake-codex")
      codex_home = Path.join(test_root, "remote-codex-home")
      port = free_port!()
      token = "worker-daemon-codex-token"
      ledger = unique_name("Session.Ledger")
      registry = unique_name("Registry")
      capacity = unique_name("Capacity")
      supervisor = unique_name("Session.Supervisor")

      File.mkdir_p!(workspace)

      File.write!(fake_codex, """
      #!/bin/sh
      count=0

      while IFS= read -r _line; do
        count=$((count + 1))

        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-worker-daemon-credential"}}}'
            while :; do sleep 1; done
            ;;
        esac
      done
      """)

      File.chmod!(fake_codex, 0o755)

      start_supervised!({SymphonyWorkerDaemon.Session.Ledger, name: ledger})
      start_supervised!({Registry, keys: :unique, name: registry})
      start_supervised!({SymphonyWorkerDaemon.CapacityManager, name: capacity, max_sessions: 1})
      start_supervised!({SymphonyWorkerDaemon.Session.Supervisor, name: supervisor, session_ledger: ledger})

      start_supervised!(
        {Bandit,
         plug:
           {SymphonyWorkerDaemon.Api,
            [
              token: token,
              session_ledger: ledger,
              registry: registry,
              capacity_manager: capacity,
              session_supervisor: supervisor,
              workspace_roots: [workspace_root],
              worker_id: "codex-worker-daemon-test",
              daemon_instance_id: "codex-worker-daemon-test-daemon",
              allowed_executables: [sh]
            ]},
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: port}
      )

      material =
        SymphonyElixir.Agent.Credential.Material.new(
          env: %{"CODEX_HOME" => codex_home},
          auth_metadata: %{
            "codex" => %{
              "credential_kind" => "codex_api_key",
              "codex_home" => codex_home,
              "api_key" => "sk-codex-worker-daemon-test"
            }
          }
        )

      target =
        SymphonyElixir.Agent.Runtime.Target.new(
          placement: :worker_daemon,
          workspace_path: workspace,
          metadata: %{
            worker_daemon_endpoint: "http://127.0.0.1:#{port}",
            run_id: "run-codex-worker-daemon-credential",
            agent_provider_kind: "codex"
          }
        )

      runtime_context =
        target
        |> SymphonyElixir.Agent.Runtime.Target.to_context()
        |> Map.merge(%{
          workspace_root: workspace_root,
          hook_timeout_ms: 10_000,
          executor_opts: [worker_daemon_token: token, worker_daemon_timeout_ms: 10_000],
          turn_sandbox_policy: %{"type" => "dangerFullAccess"}
        })

      codex_settings =
        SymphonyElixir.AgentProvider.Codex.Settings.from_options(%{
          "command_argv" => [fake_codex, "app-server"],
          "approval_policy" => "never",
          "read_timeout_ms" => 5_000,
          "turn_timeout_ms" => 10_000,
          "turn_sandbox_policy" => %{"type" => "dangerFullAccess"}
        })

      assert {:ok, session} =
               AppServer.start_session(workspace,
                 codex_settings: codex_settings,
                 provider_runtime_context: runtime_context,
                 agent_credential_material: material,
                 run_id: "run-codex-worker-daemon-credential"
               )

      assert File.exists?(Path.join(codex_home, "auth.json"))
      assert File.exists?(Path.join(codex_home, "config.toml"))

      assert :ok = AppServer.stop_session(session)
      assert wait_until(fn -> not File.exists?(codex_home) end)
    after
      File.rm_rf(test_root)
    end
  end

  test "app server rejects remote workspaces outside the configured root" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-app-server-remote-boundary-#{System.unique_integer([:positive])}"
      )

    previous_path = System.get_env("PATH")
    previous_trace = System.get_env("SYMP_TEST_SSH_TRACE")

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMP_TEST_SSH_TRACE", previous_trace)
    end)

    try do
      trace_file = Path.join(test_root, "ssh.trace")
      fake_ssh = Path.join(test_root, "ssh")

      File.mkdir_p!(test_root)
      System.put_env("SYMP_TEST_SSH_TRACE", trace_file)
      System.put_env("PATH", test_root <> ":" <> (previous_path || ""))

      File.write!(fake_ssh, """
      #!/bin/sh
      trace_file="${SYMP_TEST_SSH_TRACE:-/tmp/symphony-fake-ssh.trace}"
      printf 'ARGV:%s\\n' "$*" >> "$trace_file"
      printf '%s\\t%s\\t%s\\t%s\\n' '__SYMPHONY_WORKSPACE_ERROR__' 'workspace_outside_root' '/remote/workspaces' '/tmp/outside'
      exit 73
      """)

      File.chmod!(fake_ssh, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: "/remote/workspaces")

      issue = %Issue{
        id: "issue-remote-boundary",
        identifier: "MT-REMOTE-BOUNDARY",
        title: "Reject escaped remote workspaces",
        description: "Validate remote cwd before app-server launch",
        state: "In Progress"
      }

      assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, "/tmp/outside", "/remote/workspaces"}} =
               AppServer.run(
                 "/remote/workspaces/MT-REMOTE-BOUNDARY",
                 "Run remote worker",
                 issue,
                 codex_app_server_opts("/remote/workspaces/MT-REMOTE-BOUNDARY",
                   worker_host: "worker-01:2200"
                 )
               )
    after
      File.rm_rf(test_root)
    end
  end

  defp wait_for_os_process_exit(_kill_executable, _ps_executable, _os_pid, 0, _sleep_ms), do: false

  defp wait_for_os_process_exit(kill_executable, ps_executable, os_pid, attempts_remaining, sleep_ms)
       when is_binary(kill_executable) and is_binary(ps_executable) and is_integer(os_pid) and
              attempts_remaining > 0 do
    if os_process_alive?(kill_executable, ps_executable, os_pid) do
      Process.sleep(sleep_ms)
      wait_for_os_process_exit(kill_executable, ps_executable, os_pid, attempts_remaining - 1, sleep_ms)
    else
      true
    end
  end

  defp os_process_alive?(kill_executable, ps_executable, os_pid)
       when is_binary(kill_executable) and is_binary(ps_executable) and is_integer(os_pid) do
    case CommandEnv.system_cmd(ps_executable, ["-o", "stat=", "-p", Integer.to_string(os_pid)], stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) do
          "" -> false
          <<"Z", _::binary>> -> false
          _ -> true
        end

      _ ->
        case CommandEnv.system_cmd(kill_executable, ["-0", Integer.to_string(os_pid)], stderr_to_stdout: true) do
          {_output, 0} -> true
          _ -> false
        end
    end
  end

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp normalized_path(path) when is_binary(path) do
    path
    |> Path.expand()
    |> String.replace_prefix("/private/var/", "/var/")
  end

  defp start_mcp_wrapper!(workspace) when is_binary(workspace) do
    sh = System.find_executable("sh") || flunk("sh executable is required for this test")

    Port.open(
      {:spawn_executable, String.to_charlist(sh)},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [String.to_charlist(Tooling.wrapper_path(workspace))],
        cd: String.to_charlist(workspace)
      ]
    )
  rescue
    error in [ArgumentError, ErlangError] ->
      flunk("failed to start generated MCP wrapper: #{Exception.message(error)}")
  end

  defp close_mcp_wrapper(port) when is_port(port) do
    if Port.info(port) do
      Port.close(port)
    end
  rescue
    _error -> :ok
  after
    receive do
      {^port, {:exit_status, _status}} -> :ok
    after
      100 -> :ok
    end
  end

  defp mcp_request!(port, id, method, params) when is_port(port) do
    message = Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})

    if Port.command(port, message <> "\n") do
      wait_for_mcp_response!(port, id, "", 100)
    else
      flunk("MCP wrapper port closed before request #{id}")
    end
  end

  defp wait_for_mcp_response!(port, id, buffer, attempts_left)
       when is_port(port) and is_integer(attempts_left) and attempts_left > 0 do
    receive do
      {^port, {:data, chunk}} ->
        {lines, rest} = complete_lines(buffer <> chunk)

        case find_mcp_response(lines, id) do
          nil -> wait_for_mcp_response!(port, id, rest, attempts_left)
          response -> response
        end

      {^port, {:exit_status, status}} ->
        flunk("MCP wrapper exited before response #{id} with status #{status}; output=#{inspect(buffer)}")
    after
      50 ->
        wait_for_mcp_response!(port, id, buffer, attempts_left - 1)
    end
  end

  defp wait_for_mcp_response!(_port, id, buffer, 0) do
    flunk("timed out waiting for MCP response #{id}; buffered_output=#{inspect(buffer)}")
  end

  defp complete_lines(buffer) when is_binary(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp find_mcp_response(lines, id) when is_list(lines) do
    Enum.find_value(lines, fn line ->
      line = String.trim(line)

      with true <- String.starts_with?(line, "{"),
           {:ok, payload} <- Jason.decode(line),
           true <- payload["id"] == id do
        payload
      else
        _ -> nil
      end
    end)
  end

  defp codex_dynamic_tool_context_for_test do
    %{
      "source_context" => %{},
      "source_kind" => "composite",
      "tool_environment" => %{},
      "tool_metadata" => %{
        "linear_issue_snapshot" => %{
          "capability" => "tracker.issue_snapshot",
          "sideEffect" => "read_only",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        }
      },
      "tool_specs" => [
        %{
          "name" => "linear_issue_snapshot",
          "description" => "Read a Linear issue workflow snapshot.",
          "inputSchema" => %{
            "type" => "object",
            "required" => ["issue_id"],
            "properties" => %{"issue_id" => %{"type" => "string"}}
          }
        }
      ]
    }
  end

  @worker_daemon_process_names %{
    "Session.Ledger" => __MODULE__.SessionLedger,
    "Registry" => __MODULE__.Registry,
    "Capacity" => __MODULE__.Capacity,
    "Session.Supervisor" => __MODULE__.SessionSupervisor
  }

  defp unique_name(prefix), do: Map.fetch!(@worker_daemon_process_names, prefix)

  defp wait_until(fun, attempts_left \\ 100)

  defp wait_until(fun, attempts_left) when is_function(fun, 0) and attempts_left > 0 do
    if fun.() do
      true
    else
      Process.sleep(50)
      wait_until(fun, attempts_left - 1)
    end
  end

  defp wait_until(fun, 0) when is_function(fun, 0), do: fun.()
end
