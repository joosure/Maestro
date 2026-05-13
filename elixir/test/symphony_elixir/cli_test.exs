defmodule SymphonyElixir.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias SymphonyElixir.CLI
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.Workflow.Templates, as: WorkflowTemplates

  @ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  test "returns the guardrails acknowledgement banner when the flag is missing" do
    parent = self()

    deps = %{
      file_regular?: fn _path ->
        send(parent, :file_checked)
        true
      end,
      set_workflow_file_path: fn _path ->
        send(parent, :workflow_set)
        :ok
      end,
      set_logs_root: fn _path ->
        send(parent, :logs_root_set)
        :ok
      end,
      set_server_port_override: fn _port ->
        send(parent, :port_set)
        :ok
      end,
      validate_config: fn ->
        send(parent, :validated)
        :ok
      end,
      ensure_all_started: fn ->
        send(parent, :started)
        {:ok, [:symphony_elixir]}
      end
    }

    assert {:error, banner} = CLI.evaluate(["WORKFLOW.md"], deps)
    assert banner =~ "This Symphony implementation is a low key engineering preview."
    assert banner =~ "The configured agent provider will run without any guardrails."
    assert banner =~ "SymphonyElixir is not a supported product and is presented as-is."
    assert banner =~ @ack_flag
    refute_received :file_checked
    refute_received :workflow_set
    refute_received :logs_root_set
    refute_received :port_set
    refute_received :validated
    refute_received :started
  end

  test "defaults to WORKFLOW.md when workflow path is missing" do
    deps = %{
      file_regular?: fn path -> Path.basename(path) == "WORKFLOW.md" end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert :ok = CLI.evaluate([@ack_flag], deps)
  end

  test "uses an explicit workflow path override when provided" do
    parent = self()
    workflow_path = "tmp/custom/WORKFLOW.md"
    expanded_path = Path.expand(workflow_path)

    deps = %{
      file_regular?: fn path ->
        send(parent, {:workflow_checked, path})
        path == expanded_path
      end,
      set_workflow_file_path: fn path ->
        send(parent, {:workflow_set, path})
        :ok
      end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn ->
        send(parent, :validated)
        :ok
      end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert :ok = CLI.evaluate([@ack_flag, workflow_path], deps)
    assert_received {:workflow_checked, ^expanded_path}
    assert_received {:workflow_set, ^expanded_path}
    assert_received :validated
  end

  test "uses a workflow template alias when provided" do
    parent = self()
    {:ok, template_path} = WorkflowTemplates.resolve("tapd/cnb/opencode")

    deps = %{
      file_regular?: fn path ->
        send(parent, {:workflow_checked, path})
        path == template_path
      end,
      set_workflow_file_path: fn path ->
        send(parent, {:workflow_set, path})
        :ok
      end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert :ok = CLI.evaluate([@ack_flag, "--template", "tapd/cnb/opencode"], deps)
    assert_received {:workflow_checked, ^template_path}
    assert_received {:workflow_set, ^template_path}
  end

  test "workflow template aliases come from bundled template files" do
    aliases = WorkflowTemplates.aliases()

    assert "tapd/cnb/opencode" in aliases
    assert "tapd/cnb/claude_code" in aliases
    assert "tapd/github/codex" in aliases
    assert "linear/github/codex" in aliases
    assert "linear/github/claude_code" in aliases
    assert "linear/github/opencode.canary" in aliases
    refute "README" in aliases
    assert Enum.all?(aliases, &(length(Path.split(&1)) == 3))
  end

  test "rejects ambiguous workflow template and path selectors" do
    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "--template", "tapd/cnb/opencode", "WORKFLOW.md"], deps)
    assert message == "Pass either --template or a workflow path, not both"
  end

  test "rejects workflow template aliases outside the template root" do
    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "--template", "../WORKFLOW"], deps)
    assert message =~ "Workflow template alias must stay under"
  end

  test "accepts --logs-root and passes an expanded root to runtime deps" do
    parent = self()

    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn path ->
        send(parent, {:logs_root, path})
        :ok
      end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert :ok = CLI.evaluate([@ack_flag, "--logs-root", "tmp/custom-logs", "WORKFLOW.md"], deps)
    assert_received {:logs_root, expanded_path}
    assert expanded_path == Path.expand("tmp/custom-logs")
  end

  test "returns not found when workflow file does not exist" do
    deps = %{
      file_regular?: fn _path -> false end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Workflow file not found:"
  end

  test "returns startup error when app cannot start" do
    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:error, :boom} end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Failed to start Symphony with workflow"
    assert message =~ ":boom"
  end

  test "returns ok when workflow exists and app starts" do
    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn -> :ok end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert :ok = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
  end

  test "fails fast on invalid config before starting the application" do
    parent = self()

    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn ->
        send(parent, :validated)
        {:error, :missing_tracker_kind}
      end,
      ensure_all_started: fn ->
        send(parent, :started)
        {:ok, [:symphony_elixir]}
      end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Configuration error:"
    assert message =~ ":missing_tracker_kind"
    assert_received :validated
    refute_received :started
  end

  test "formats repo-provider validation errors with their message" do
    deps = %{
      file_regular?: fn _path -> true end,
      set_workflow_file_path: fn _path -> :ok end,
      set_logs_root: fn _path -> :ok end,
      set_server_port_override: fn _port -> :ok end,
      validate_config: fn ->
        {:error,
         %RepoProviderError{
           code: :unsupported_option,
           provider: "cnb",
           operation: :validate_config,
           message: "repo.provider.options.required_pr_label requires repo.provider.kind to be github; current provider: cnb"
         }}
      end,
      ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
    }

    assert {:error, message} = CLI.evaluate([@ack_flag, "WORKFLOW.md"], deps)
    assert message =~ "Configuration error:"
    assert message =~ "repo.provider.options.required_pr_label requires repo.provider.kind to be github"
    assert message =~ "tracker and repo provider settings"
  end

  test "accounts login reads token source and delegates without guardrail acknowledgement" do
    parent = self()
    token_env = "SYMPHONY_CLI_TEST_TOKEN_#{System.unique_integer([:positive])}"
    System.put_env(token_env, "opencode-cli-token")
    on_exit(fn -> System.delete_env(token_env) end)

    deps =
      account_cli_deps(%{
        accounts_login: fn provider_kind, id, opts ->
          send(parent, {:login, provider_kind, id, opts})
          {:ok, %{agent_provider_kind: "opencode", id: id, email: Keyword.get(opts, :email)}}
        end
      })

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.evaluate(
                   [
                     "accounts",
                     "login",
                     "opencode",
                     "primary",
                     "--email",
                     "ops@example.com",
                     "--env-name",
                     "OPENROUTER_API_KEY",
                     "--token-env",
                     token_env
                   ],
                   deps
                 )
      end)

    assert output =~ "Stored opencode account primary (ops@example.com)"
    assert_received {:login, "opencode", "primary", opts}
    assert Keyword.get(opts, :token) == "opencode-cli-token"
    assert Keyword.get(opts, :env_name) == "OPENROUTER_API_KEY"
    refute Keyword.has_key?(opts, :token_env)
  end

  test "accounts login supports Codex API-key token source" do
    parent = self()
    token_env = "SYMPHONY_CLI_TEST_CODEX_TOKEN_#{System.unique_integer([:positive])}"
    System.put_env(token_env, "codex-cli-token")
    on_exit(fn -> System.delete_env(token_env) end)

    deps =
      account_cli_deps(%{
        accounts_login: fn provider_kind, id, opts ->
          send(parent, {:login, provider_kind, id, opts})
          {:ok, %{agent_provider_kind: "codex", id: id, email: Keyword.get(opts, :email)}}
        end
      })

    output =
      capture_io(fn ->
        assert :ok =
                 CLI.evaluate(
                   [
                     "accounts",
                     "login",
                     "codex",
                     "openai",
                     "--email",
                     "openai@example.com",
                     "--token-env",
                     token_env
                   ],
                   deps
                 )
      end)

    assert output =~ "Stored codex account openai (openai@example.com)"
    assert_received {:login, "codex", "openai", opts}
    assert Keyword.get(opts, :token) == "codex-cli-token"
    refute Keyword.has_key?(opts, :env_name)
    refute Keyword.has_key?(opts, :token_env)
  end

  test "accounts verify prints OpenCode account verification output" do
    deps =
      account_cli_deps(%{
        accounts_verify: fn "opencode", "openrouter", opts ->
          assert opts == []

          {:ok,
           %{
             account: %{
               agent_provider_kind: "opencode",
               id: "openrouter",
               credential_kind: "opencode_env_token"
             },
             output: "opencode 1.2.3"
           }}
        end
      })

    output =
      capture_io(fn ->
        assert :ok = CLI.evaluate(["accounts", "verify", "opencode", "openrouter"], deps)
      end)

    assert output =~ "Verified opencode account openrouter"
    assert output =~ "opencode 1.2.3"
  end

  test "accounts list prints provider-neutral account summaries" do
    deps =
      account_cli_deps(%{
        accounts_list: fn nil ->
          {:ok,
           [
             %{
               agent_provider_kind: "claude_code",
               id: "primary",
               email: "ops@example.com",
               state: "healthy",
               credential_kind: "claude_oauth_token"
             }
           ]}
        end
      })

    output =
      capture_io(fn ->
        assert :ok = CLI.evaluate(["accounts", "list"], deps)
      end)

    assert output =~ "claude_code\tprimary\tops@example.com\thealthy\tclaude_oauth_token\t-"
  end

  test "accounts remove normalizes provider aliases in operator output" do
    deps =
      account_cli_deps(%{
        accounts_remove: fn "claude", "primary" -> :ok end
      })

    output =
      capture_io(fn ->
        assert :ok = CLI.evaluate(["accounts", "remove", "claude", "primary"], deps)
      end)

    assert output == "Removed claude_code account primary\n"
  end

  defp account_cli_deps(overrides) do
    Map.merge(
      %{
        file_regular?: fn _path -> false end,
        set_workflow_file_path: fn _path -> :ok end,
        set_logs_root: fn _path -> :ok end,
        set_server_port_override: fn _port -> :ok end,
        validate_config: fn -> :ok end,
        ensure_all_started: fn -> {:ok, [:symphony_elixir]} end
      },
      overrides
    )
  end
end
