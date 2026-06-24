defmodule SymphonyElixir.Release.CredentialPreflightTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.AgentProvider.ReleaseCredentialPreflight, as: ProviderPreflight
  alias SymphonyElixir.Release.CredentialPreflight
  alias SymphonyElixir.Release.WorkflowSource
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.Template, as: TemplateRegistry
  @auth_probe_opts [auth_probe: true, prompt: "Reply with exactly OK."]

  test "logs in and verifies CodeBuddy credentials from environment" do
    parent = self()
    store_root = Path.join(System.tmp_dir!(), "release-runner-codebuddy-store")

    deps =
      preflight_deps(parent,
        settings: settings(codebuddy_provider_kind(), codebuddy_default_credential_ref(), store_root)
      )

    template_alias = tapd_cnb_codebuddy_template_alias()
    template_path = Path.join(["/templates", template_alias <> ".md"])

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => template_alias,
      "CODEBUDDY_API_KEY" => "ck-test",
      "CODEBUDDY_INTERNET_ENVIRONMENT" => "internal"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:resolve_template, ^template_alias}
    assert_received {:set_workflow_file_path, ^template_path}

    assert_received {:accounts_login, "codebuddy_code", "default", login_opts, login_store_opts}
    assert Keyword.fetch!(login_opts, :token) == "ck-test"
    assert Keyword.fetch!(login_opts, :internet_environment) == "internal"
    assert get_in(login_store_opts, [:agent, :credentials, :store_root]) == store_root

    assert_received {:accounts_verify, "codebuddy_code", "default", @auth_probe_opts, _verify_store_opts}
  end

  test "resolves OpenCode credential env name from account id" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", "credential://opencode/zai", "/tmp/release-runner-opencode-store", credential_ref_key: :atom)
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md",
      "ZAI_API_KEY" => "zai-token"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    refute_received {:resolve_template, _template}
    assert_received {:set_workflow_file_path, "/app/WORKFLOW.local.md"}

    assert_received {:accounts_login, "opencode", "zai", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :env_name) == "ZAI_API_KEY"
    assert Keyword.fetch!(login_opts, :token) == "zai-token"

    assert_received {:accounts_verify, "opencode", "zai", @auth_probe_opts, _verify_store_opts}
  end

  test "logs in and verifies Codex credentials from environment" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("codex", "credential://codex/default", "/tmp/release-runner-codex-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.codex.local.md",
      "OPENAI_API_KEY" => "sk-test"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:accounts_login, "codex", "default", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :token) == "sk-test"

    assert_received {:accounts_verify, "codex", "default", [], _verify_store_opts}
  end

  test "logs in and verifies Claude Code credentials from OAuth token environment" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("claude_code", "credential://claude_code/default", "/tmp/release-runner-claude-code-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.claude.local.md",
      "CLAUDE_CODE_OAUTH_TOKEN" => "oauth-token"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:accounts_login, "claude_code", "default", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :token) == "oauth-token"

    assert_received {:accounts_verify, "claude_code", "default", [], _verify_store_opts}
  end

  test "skips workflows without credential_ref in auto mode" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", nil, "/tmp/release-runner-skip-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => linear_github_opencode_template_alias()
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:log, "Managed credential preflight skipped: workflow has no agent_provider.options.credential_ref."}
    refute_received {:accounts_login, _, _, _, _}
    refute_received {:accounts_verify, _, _, _, _}
  end

  test "verifies existing credential when token is missing" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings(codebuddy_provider_kind(), codebuddy_default_credential_ref(), "/tmp/release-runner-existing-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => tapd_cnb_codebuddy_template_alias()
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    refute_received {:accounts_login, _, _, _, _}
    assert_received {:accounts_verify, "codebuddy_code", "default", @auth_probe_opts, _verify_store_opts}
  end

  test "explains how to initialize missing persisted credentials" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings(codebuddy_provider_kind(), codebuddy_default_credential_ref(), "/tmp/release-runner-missing-store"),
        verify_result: {:error, :managed_credential_not_configured}
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => tapd_cnb_codebuddy_template_alias()
    }

    assert {:error, message} = CredentialPreflight.run_from_env(env, deps)

    assert message ==
             "Managed credential preflight failed: codebuddy_code/default: :managed_credential_not_configured; if this credential is not initialized or needs rotation, set CODEBUDDY_API_KEY to create or update it automatically"

    refute_received {:accounts_login, _, _, _, _}
    assert_received {:accounts_verify, "codebuddy_code", "default", @auth_probe_opts, _verify_store_opts}
  end

  test "explains how to initialize unknown OpenCode accounts without a token env" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", "credential://opencode/custom", "/tmp/release-runner-custom-opencode-store"),
        verify_result: {:error, :managed_credential_not_configured}
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md"
    }

    assert {:error, message} = CredentialPreflight.run_from_env(env, deps)

    assert message ==
             "Managed credential preflight failed: opencode/custom: :managed_credential_not_configured; if this credential is not initialized or needs rotation, set SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME to the environment variable name OpenCode should receive, then set that environment variable to the token or set SYMPHONY_OPENCODE_TOKEN_ENV to another token environment variable name"

    refute_received {:accounts_login, _, _, _, _}
    assert_received {:accounts_verify, "opencode", "custom", @auth_probe_opts, _verify_store_opts}
  end

  test "requires credential_ref when preflight mode is required" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", nil, "/tmp/release-runner-required-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "required",
      WorkflowSource.template_env() => linear_github_opencode_template_alias()
    }

    assert {:error, message} = CredentialPreflight.run_from_env(env, deps)

    assert message ==
             "Managed credential preflight failed: #{CredentialPreflight.preflight_env()}=required but workflow has no agent_provider.options.credential_ref"

    refute_received {:accounts_login, _, _, _, _}
    refute_received {:accounts_verify, _, _, _, _}
  end

  test "uses explicit account id for credential pool refs" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings(codebuddy_provider_kind(), codebuddy_pool_credential_ref(), "/tmp/release-runner-pool-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => tapd_cnb_codebuddy_template_alias(),
      CredentialPreflight.account_id_env() => "selected",
      "CODEBUDDY_API_KEY" => "ck-selected"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:accounts_login, "codebuddy_code", "selected", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :token) == "ck-selected"

    assert_received {:accounts_verify, "codebuddy_code", "selected", @auth_probe_opts, _verify_store_opts}
  end

  test "rejects unsupported provider kinds" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("mock", "credential://mock/default", "/tmp/release-runner-unsupported-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md"
    }

    assert {:error, message} = CredentialPreflight.run_from_env(env, deps)

    assert message ==
             "Managed credential preflight failed: container managed credential preflight supports claude_code, codebuddy_code, codex, opencode, got mock"

    refute_received {:accounts_login, _, _, _, _}
    refute_received {:accounts_verify, _, _, _, _}
  end

  test "trims CodeBuddy token env override before reading the token" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings(codebuddy_provider_kind(), codebuddy_default_credential_ref(), "/tmp/release-runner-codebuddy-env-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.template_env() => tapd_cnb_codebuddy_template_alias(),
      "SYMPHONY_CODEBUDDY_TOKEN_ENV" => " CODEBUDDY_CUSTOM_KEY ",
      "CODEBUDDY_CUSTOM_KEY" => "ck-custom"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:accounts_login, "codebuddy_code", "default", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :token) == "ck-custom"
  end

  test "logs in unknown OpenCode accounts with custom env-name and token env" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", "credential://opencode/custom", "/tmp/release-runner-opencode-custom-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md",
      "SYMPHONY_OPENCODE_CREDENTIAL_ENV_NAME" => " CUSTOM_API_KEY ",
      "SYMPHONY_OPENCODE_TOKEN_ENV" => " CUSTOM_TOKEN ",
      "CUSTOM_TOKEN" => "custom-token"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)

    assert_received {:accounts_login, "opencode", "custom", login_opts, _login_store_opts}
    assert Keyword.fetch!(login_opts, :env_name) == "CUSTOM_API_KEY"
    assert Keyword.fetch!(login_opts, :token) == "custom-token"

    assert_received {:accounts_verify, "opencode", "custom", @auth_probe_opts, _verify_store_opts}
  end

  test "can use command-only credential verification mode" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings: settings("opencode", "credential://opencode/zai", "/tmp/release-runner-command-verify-store")
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md",
      ProviderPreflight.verify_mode_env() => "command",
      "ZAI_API_KEY" => "zai-token"
    }

    assert :ok = CredentialPreflight.run_from_env(env, deps)
    assert_received {:accounts_verify, "opencode", "zai", [], _verify_store_opts}
  end

  test "returns settings errors without rescuing them as successful configuration" do
    parent = self()

    deps =
      preflight_deps(parent,
        settings_result: {:error, {:missing_workflow_file, "/app/WORKFLOW.local.md", :enoent}}
      )

    env = %{
      CredentialPreflight.preflight_env() => "auto",
      WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md"
    }

    assert {:error, message} = CredentialPreflight.run_from_env(env, deps)
    assert message == "Managed credential preflight failed: Missing WORKFLOW.md at /app/WORKFLOW.local.md: :enoent"

    assert_received {:set_workflow_file_path, "/app/WORKFLOW.local.md"}
    refute_received {:accounts_login, _, _, _, _}
    refute_received {:accounts_verify, _, _, _, _}
  end

  defp preflight_deps(parent, opts) do
    verify_result = Keyword.get(opts, :verify_result, {:ok, %{output: "ok"}})
    settings_result = Keyword.get_lazy(opts, :settings_result, fn -> {:ok, Keyword.fetch!(opts, :settings)} end)

    %{
      accounts_login: fn provider_kind, id, login_opts, store_opts ->
        send(parent, {:accounts_login, provider_kind, id, login_opts, store_opts})
        {:ok, %{agent_provider_kind: provider_kind, id: id}}
      end,
      accounts_verify: fn provider_kind, id, verify_opts, store_opts ->
        send(parent, {:accounts_verify, provider_kind, id, verify_opts, store_opts})
        verify_result
      end,
      resolve_template: fn template ->
        send(parent, {:resolve_template, template})
        {:ok, Path.join(["/templates", template <> ".md"])}
      end,
      set_workflow_file_path: fn path ->
        send(parent, {:set_workflow_file_path, path})
        :ok
      end,
      settings: fn -> settings_result end,
      log: fn message -> send(parent, {:log, message}) end
    }
  end

  defp settings(provider_kind, credential_ref, store_root, opts \\ []) do
    credential_options =
      case Keyword.get(opts, :credential_ref_key, :string) do
        :atom -> %{credential_ref: credential_ref}
        _key -> %{"credential_ref" => credential_ref}
      end

    %{
      agent: %{
        credentials: %{
          enabled: true,
          store_root: store_root,
          exhausted_cooldown_ms: 60_000
        }
      },
      agent_provider: %{
        kind: provider_kind,
        options: credential_options
      }
    }
  end

  defp linear_github_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.opencode()
    )
  end

  defp tapd_cnb_codebuddy_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.tapd(),
      RepoProviderKinds.cnb(),
      AgentProviderKinds.codebuddy_code()
    )
  end

  defp tapd_cnb_codebuddy_template_entry do
    {:ok, entry} = TemplateRegistry.fetch(tapd_cnb_codebuddy_template_alias())
    entry
  end

  defp codebuddy_provider_kind, do: tapd_cnb_codebuddy_template_entry().agent_provider_kind
  defp codebuddy_default_credential_ref, do: tapd_cnb_codebuddy_template_entry().credential_ref
  defp codebuddy_pool_credential_ref, do: "credential://#{codebuddy_provider_kind()}/*"
end
