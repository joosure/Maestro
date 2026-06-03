defmodule SymphonyElixir.Agent.Credential.AccountsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Credential.Accounts

  test "Claude operator login stores OAuth token under canonical provider kind" do
    store_root = temp_store_root!("login")
    opts = store_opts(store_root)

    assert {:ok, account} =
             Accounts.login("claude", "primary", [email: "primary@example.com", token: "sk-ant-oat-test"], opts)

    assert account.agent_provider_kind == "claude_code"
    assert account.credential_kind == "claude_oauth_token"
    assert File.read!(account.secret_file) == "sk-ant-oat-test\n"

    assert {:ok, metadata} = account.account_dir |> Path.join("metadata.json") |> File.read!() |> Jason.decode()
    refute Map.has_key?(metadata, "token")
  end

  test "OpenCode operator login stores env-token credentials without metadata secret material" do
    store_root = temp_store_root!("opencode-login")
    opts = store_opts(store_root)

    assert {:ok, account} =
             Accounts.login(
               "opencode",
               "openrouter",
               [email: "openrouter@example.com", env_name: "OPENROUTER_API_KEY", token: "sk-or-test"],
               opts
             )

    assert account.agent_provider_kind == "opencode"
    assert account.credential_kind == "opencode_env_token"
    assert account.env_name == "OPENROUTER_API_KEY"
    assert File.read!(account.secret_file) == "sk-or-test\n"
    assert Accounts.credential_env(account) == [{"OPENROUTER_API_KEY", "sk-or-test"}]

    assert {:ok, metadata} = account.account_dir |> Path.join("metadata.json") |> File.read!() |> Jason.decode()
    assert metadata["env_name"] == "OPENROUTER_API_KEY"
    refute Map.has_key?(metadata, "token")
  end

  test "CodeBuddy operator login stores API-key credentials with internet environment metadata" do
    store_root = temp_store_root!("codebuddy-login")
    opts = store_opts(store_root)

    assert {:ok, account} =
             Accounts.login(
               "codebuddy",
               "china",
               [email: "codebuddy@example.com", internet_environment: "internal", token: "ck-test"],
               opts
             )

    assert account.agent_provider_kind == "codebuddy_code"
    assert account.credential_kind == "codebuddy_env_token"
    assert account.internet_environment == "internal"
    assert File.read!(account.secret_file) == "ck-test\n"

    assert Accounts.credential_env(account) == [
             {"CODEBUDDY_API_KEY", "ck-test"},
             {"CODEBUDDY_API_KEY_DISABLED", nil},
             {"CODEBUDDY_AUTH_TOKEN", nil},
             {"CODEBUDDY_BASE_URL", nil},
             {"CODEBUDDY_INTERNET_ENVIRONMENT", "internal"}
           ]

    assert {:ok, metadata} = account.account_dir |> Path.join("metadata.json") |> File.read!() |> Jason.decode()
    assert metadata["internet_environment"] == "internal"
    refute Map.has_key?(metadata, "token")
    refute Map.has_key?(metadata, "CODEBUDDY_API_KEY")
  end

  test "CodeBuddy login validates internet environment" do
    store_root = temp_store_root!("codebuddy-invalid-env")
    opts = store_opts(store_root)

    assert {:error, {:invalid_codebuddy_internet_environment, "moon"}} =
             Accounts.login("codebuddy_code", "primary", [internet_environment: "moon", token: "ck-test"], opts)
  end

  test "Codex operator login stores API-key credentials without env metadata" do
    store_root = temp_store_root!("codex-login")
    opts = store_opts(store_root)

    assert {:ok, account} =
             Accounts.login(
               "codex",
               "openai",
               [email: "openai@example.com", token: "sk-codex-test"],
               opts
             )

    assert account.agent_provider_kind == "codex"
    assert account.credential_kind == "codex_api_key"
    assert File.read!(account.secret_file) == "sk-codex-test\n"
    assert Accounts.credential_env(account) == []

    assert {:ok, metadata} = account.account_dir |> Path.join("metadata.json") |> File.read!() |> Jason.decode()
    refute Map.has_key?(metadata, "token")
    refute Map.has_key?(metadata, "OPENAI_API_KEY")
  end

  test "Claude import copies provider config into provider-neutral auth dir" do
    store_root = temp_store_root!("import")
    source_dir = temp_store_root!("source")
    opts = store_opts(store_root)
    File.mkdir_p!(source_dir)
    File.write!(Path.join(source_dir, "settings.json"), ~s({"theme":"dark"}))

    assert {:ok, account} =
             Accounts.import_account("claude_code", "imported", [email: "imported@example.com", from: source_dir], opts)

    assert account.credential_kind == "claude_config"
    assert File.read!(Path.join(account.auth_dir, "settings.json")) == ~s({"theme":"dark"})
  end

  test "Claude setup-token command output can seed an operator login" do
    parent = self()
    store_root = temp_store_root!("setup-token")
    opts = store_opts(store_root)

    runner = fn executable, args, env, run_opts ->
      send(parent, {:setup_token, executable, args, env, Keyword.take(run_opts, [:stream, :tty_capture, :transcript_path])})
      {:ok, "Generated token: sk-ant-oat-generated"}
    end

    assert {:ok, account} = Accounts.login("claude_code", "generated", [runner: runner], opts)
    assert File.read!(account.secret_file) == "sk-ant-oat-generated\n"

    assert_received {:setup_token, "claude", ["setup-token"], [], setup_opts}

    assert Keyword.fetch!(setup_opts, :stream)
    assert Keyword.fetch!(setup_opts, :tty_capture)
    transcript_path = Keyword.fetch!(setup_opts, :transcript_path)
    assert transcript_path == Path.join(account.account_dir, "claude_setup_token.transcript")
  end

  test "verify uses materialized Claude environment without leaking through config" do
    parent = self()
    store_root = temp_store_root!("verify")
    opts = store_opts(store_root)
    {:ok, _account} = Accounts.login("claude_code", "primary", [token: "sk-ant-oat-verify"], opts)

    runner = fn executable, args, env, _run_opts ->
      send(parent, {:provider_command, executable, args, env})
      {:ok, ~s({"status":"ok"})}
    end

    assert {:ok, result} = Accounts.verify("claude", "primary", [runner: runner], opts)
    assert result.account.agent_provider_kind == "claude_code"
    assert result.output == ~s({"status":"ok"})

    assert_received {:provider_command, "claude", ["auth", "status", "--json"], env}
    assert {"CLAUDE_CODE_OAUTH_TOKEN", "sk-ant-oat-verify"} in env
    assert {"CLAUDE_CONFIG_DIR", _auth_dir} = Enum.find(env, &(elem(&1, 0) == "CLAUDE_CONFIG_DIR"))
    assert {"ANTHROPIC_API_KEY", ""} in env
  end

  test "verify uses materialized OpenCode env-token environment" do
    parent = self()
    store_root = temp_store_root!("opencode-verify")
    opts = store_opts(store_root)

    {:ok, _account} =
      Accounts.login(
        "opencode",
        "openrouter",
        [env_name: "OPENROUTER_API_KEY", token: "sk-or-verify"],
        opts
      )

    runner = fn executable, args, env, _run_opts ->
      send(parent, {:provider_command, executable, args, env})
      {:ok, "opencode 1.2.3"}
    end

    assert {:ok, result} = Accounts.verify("opencode", "openrouter", [runner: runner], opts)
    assert result.account.agent_provider_kind == "opencode"
    assert result.account.credential_kind == "opencode_env_token"
    assert result.account.env_name == "OPENROUTER_API_KEY"
    assert result.output == "opencode 1.2.3"

    assert_received {:provider_command, "opencode", ["--version"], env}
    assert {"OPENROUTER_API_KEY", "sk-or-verify"} in env
  end

  test "verify can run OpenCode non-interactive auth probe" do
    parent = self()
    store_root = temp_store_root!("opencode-auth-probe")
    opts = store_opts(store_root)

    {:ok, _account} =
      Accounts.login(
        "opencode",
        "openrouter",
        [env_name: "OPENROUTER_API_KEY", token: "sk-or-probe"],
        opts
      )

    runner = fn executable, args, env, _run_opts ->
      send(parent, {:provider_command, executable, args, env})
      {:ok, ~s({"message":"OK"})}
    end

    assert {:ok, result} =
             Accounts.verify(
               "opencode",
               "openrouter",
               [runner: runner, auth_probe: true, prompt: "Reply OK.", model: "openrouter/test-model"],
               opts
             )

    assert result.output == ~s({"message":"OK"})

    assert_received {:provider_command, "opencode", ["run", "--format", "json", "--model", "openrouter/test-model", "Reply OK."], env}

    assert {"OPENROUTER_API_KEY", "sk-or-probe"} in env
  end

  test "verify uses materialized CodeBuddy API-key environment" do
    parent = self()
    store_root = temp_store_root!("codebuddy-verify")
    opts = store_opts(store_root)

    {:ok, _account} =
      Accounts.login(
        "codebuddy",
        "china",
        [internet_environment: "ioa", token: "ck-verify"],
        opts
      )

    runner = fn executable, args, env, _run_opts ->
      send(parent, {:provider_command, executable, args, env})
      {:ok, "2.97.2"}
    end

    assert {:ok, result} = Accounts.verify("codebuddy", "china", [runner: runner], opts)
    assert result.account.agent_provider_kind == "codebuddy_code"
    assert result.account.credential_kind == "codebuddy_env_token"
    assert result.account.internet_environment == "ioa"
    assert result.output == "2.97.2"

    assert_received {:provider_command, "codebuddy", ["--version"], env}
    assert {"CODEBUDDY_API_KEY", "ck-verify"} in env
    assert {"CODEBUDDY_INTERNET_ENVIRONMENT", "ioa"} in env
    assert {"CODEBUDDY_AUTH_TOKEN", ""} in env
    assert {"CODEBUDDY_BASE_URL", ""} in env
  end

  test "verify can run CodeBuddy non-interactive auth probe" do
    parent = self()
    store_root = temp_store_root!("codebuddy-auth-probe")
    opts = store_opts(store_root)

    {:ok, _account} =
      Accounts.login(
        "codebuddy",
        "china",
        [internet_environment: "internal", token: "ck-probe"],
        opts
      )

    runner = fn executable, args, env, _run_opts ->
      send(parent, {:provider_command, executable, args, env})
      {:ok, "OK"}
    end

    assert {:ok, result} =
             Accounts.verify(
               "codebuddy",
               "china",
               [runner: runner, auth_probe: true, prompt: "Reply OK.", model: "codebuddy-test"],
               opts
             )

    assert result.output == "OK"

    assert_received {:provider_command, "codebuddy", ["-p", "Reply OK.", "--output-format", "text", "--max-turns", "1", "--tools", "", "--model", "codebuddy-test"], env}

    assert {"CODEBUDDY_API_KEY", "ck-probe"} in env
    assert {"CODEBUDDY_INTERNET_ENVIRONMENT", "internal"} in env
  end

  test "verify uses materialized Codex CODEX_HOME instead of OPENAI_API_KEY env injection" do
    parent = self()
    store_root = temp_store_root!("codex-verify")
    material_root = temp_store_root!("codex-verify-material")
    opts = store_opts(store_root)

    {:ok, _account} =
      Accounts.login(
        "codex",
        "openai",
        [token: "sk-codex-verify"],
        opts
      )

    runner = fn executable, args, env, _run_opts ->
      codex_home = env |> Enum.find(&(elem(&1, 0) == "CODEX_HOME")) |> elem(1)
      config = codex_home |> Path.join("config.toml") |> File.read!()
      auth = codex_home |> Path.join("auth.json") |> File.read!() |> Jason.decode!()

      send(parent, {:provider_command, executable, args, env, codex_home, config, auth})
      {:ok, "Logged in using an API key"}
    end

    assert {:ok, result} =
             Accounts.verify(
               "codex",
               "openai",
               [runner: runner, codex_credential_material_root: material_root],
               opts
             )

    assert result.account.agent_provider_kind == "codex"
    assert result.account.credential_kind == "codex_api_key"

    assert_received {:provider_command, "codex", ["login", "status"], env, codex_home, config, auth}
    assert {"CODEX_HOME", ^codex_home} = Enum.find(env, &(elem(&1, 0) == "CODEX_HOME"))
    refute Enum.any?(env, &(elem(&1, 0) == "OPENAI_API_KEY"))
    assert config == "cli_auth_credentials_store = \"file\"\n"
    assert auth["auth_mode"] == "apikey"
    assert auth["OPENAI_API_KEY"] == "sk-codex-verify"
    refute File.exists?(codex_home)
  end

  test "verify redacts Codex auth file output on command failure" do
    store_root = temp_store_root!("codex-verify-redaction")
    material_root = temp_store_root!("codex-verify-redaction-material")
    opts = store_opts(store_root)
    command = Path.join(store_root, "fake-codex")

    {:ok, _account} =
      Accounts.login(
        "codex",
        "openai",
        [token: "sk-codex-redact"],
        opts
      )

    File.write!(command, """
    #!/bin/sh
    cat "$CODEX_HOME/auth.json"
    exit 1
    """)

    File.chmod!(command, 0o755)

    assert {:error, %{exit_status: 1, output: output}} =
             Accounts.verify(
               "codex",
               "openai",
               [command: command, codex_credential_material_root: material_root],
               opts
             )

    assert output =~ ~s("OPENAI_API_KEY":"[REDACTED]")
    refute output =~ "sk-codex-redact"
  end

  test "verify redacts OpenCode env-token output on command failure" do
    store_root = temp_store_root!("opencode-verify-redaction")
    opts = store_opts(store_root)
    command = Path.join(store_root, "fake-opencode")

    {:ok, _account} =
      Accounts.login(
        "opencode",
        "openrouter",
        [env_name: "OPENROUTER_API_KEY", token: "sk-or-redact"],
        opts
      )

    File.write!(command, """
    #!/bin/sh
    printf 'OPENROUTER_API_KEY=%s\\n' "$OPENROUTER_API_KEY"
    exit 1
    """)

    File.chmod!(command, 0o755)

    assert {:error, %{exit_status: 1, output: output}} =
             Accounts.verify("opencode", "openrouter", [command: command], opts)

    assert output =~ "OPENROUTER_API_KEY=[REDACTED]"
    refute output =~ "sk-or-redact"
  end

  test "verify redacts CodeBuddy API-key output on command failure" do
    store_root = temp_store_root!("codebuddy-verify-redaction")
    opts = store_opts(store_root)
    command = Path.join(store_root, "fake-codebuddy")

    {:ok, _account} =
      Accounts.login(
        "codebuddy",
        "china",
        [internet_environment: "internal", token: "ck-redact"],
        opts
      )

    File.write!(command, """
    #!/bin/sh
    printf 'CODEBUDDY_API_KEY=%s\\n' "$CODEBUDDY_API_KEY"
    exit 1
    """)

    File.chmod!(command, 0o755)

    assert {:error, %{exit_status: 1, output: output}} =
             Accounts.verify("codebuddy", "china", [command: command], opts)

    assert output =~ "CODEBUDDY_API_KEY=[REDACTED]"
    refute output =~ "ck-redact"
  end

  test "account lifecycle commands operate through canonical provider records" do
    store_root = temp_store_root!("lifecycle")
    opts = store_opts(store_root)
    {:ok, _account} = Accounts.login("claude", "primary", [token: "sk-ant-oat-life"], opts)

    assert {:ok, [listed]} = Accounts.list("claude", opts)
    assert listed.agent_provider_kind == "claude_code"
    assert {:ok, [_listed]} = Accounts.list(nil, opts)

    assert {:ok, paused} = Accounts.pause("claude", "primary", [reason: "maintenance"], opts)
    assert paused.state == "paused"

    assert {:ok, disabled} = Accounts.disable("claude", "primary", opts)
    assert disabled.state == "disabled"

    assert {:ok, enabled} = Accounts.enable("claude", "primary", opts)
    assert enabled.state == "unknown"

    assert {:ok, resumed} = Accounts.resume("claude", "primary", opts)
    assert resumed.state == "unknown"

    assert :ok = Accounts.remove("claude", "primary", opts)
    assert {:ok, []} = Accounts.list("claude", opts)
  end

  test "credential env supports imported Claude config without token material" do
    store_root = temp_store_root!("env")
    source_dir = temp_store_root!("env-source")
    File.mkdir_p!(source_dir)
    File.write!(Path.join(source_dir, ".claude.json"), "{}")

    {:ok, account} =
      Accounts.import_account("claude", "config", [from: source_dir], store_opts(store_root))

    assert Accounts.credential_env(account) == [
             {"CLAUDE_CONFIG_DIR", account.auth_dir},
             {"ANTHROPIC_API_KEY", ""}
           ]
  end

  test "import and verify fail explicitly for unsupported or missing provider state" do
    store_root = temp_store_root!("errors")
    opts = store_opts(store_root)

    assert {:error, {:missing_claude_config, _source_dir}} =
             Accounts.import_account("claude_code", "missing", [from: temp_store_root!("missing-source")], opts)

    assert {:error, {:unsupported_account_import_provider, "opencode"}} =
             Accounts.import_account("opencode", "primary", [], opts)

    assert {:error, :not_found} = Accounts.verify("claude_code", "absent", [], opts)
  end

  test "unsupported provider logins fail explicitly" do
    store_root = temp_store_root!("unsupported")
    opts = store_opts(store_root)

    assert {:error, :missing_opencode_env_name} =
             Accounts.login("opencode", "primary", [token: "secret"], opts)

    assert {:error, :missing_codex_api_key} =
             Accounts.login("codex", "primary", [], opts)

    assert {:error, :missing_codebuddy_api_key} =
             Accounts.login("codebuddy", "primary", [], opts)

    assert {:error, {:unsupported_account_login_provider, "future_provider"}} =
             Accounts.login("future_provider", "primary", [token: "secret"], opts)
  end

  test "provider aliases normalize only at the operator boundary" do
    assert Accounts.normalize_provider_kind("claude") == "claude_code"
    assert Accounts.normalize_provider_kind("open_code") == "opencode"
    assert Accounts.normalize_provider_kind("future_provider") == "future_provider"
    assert Accounts.normalize_provider_kind("  ") == nil
  end

  defp temp_store_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-agent-credential-accounts-#{suffix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp store_opts(store_root) do
    %{agent: %{credentials: %{enabled: true, store_root: store_root, exhausted_cooldown_ms: 60_000}}}
  end
end
