defmodule SymphonyElixir.ClaudeCodeCredentialQuotaTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.AgentProvider.ClaudeCode.{Adapter, RateLimitProbe}
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig

  test "Claude materializer turns a managed OAuth account into provider env only" do
    store_root = temp_store_root!("materialize")
    enable_credentials!(store_root)

    {:ok, account} =
      Store.create_or_update("claude_code", "primary", email: "primary@example.com")

    File.write!(account.secret_file, "oauth-secret\n")

    assert {:ok, lease} =
             Store.acquire("claude_code", "credential://claude_code/primary", run_id: "run-materialize")

    config = ProviderConfig.new(%{kind: "claude_code", options: %{}})
    assert {:ok, material} = Adapter.materialize_credential(config, lease, [])

    assert material.env == %{
             "ANTHROPIC_API_KEY" => "",
             "CLAUDE_CODE_OAUTH_TOKEN" => "oauth-secret",
             "CLAUDE_CONFIG_DIR" => account.auth_dir
           }

    refute inspect(material.summary) =~ "oauth-secret"
  end

  test "Claude quota probe parses Anthropic unified headers into a common snapshot and store state" do
    store_root = temp_store_root!("quota")

    enable_credentials!(store_root,
      agent_quota_preflight: "required",
      agent_provider_kind: "claude_code",
      agent_provider_options: %{credential_ref: "credential://claude_code/primary"}
    )

    {:ok, account} =
      Store.create_or_update("claude_code", "primary", email: "primary@example.com")

    File.write!(account.secret_file, "oauth-secret\n")

    req_fun = fn payload, headers ->
      send(self(), {:quota_request, payload, headers})

      {:ok,
       %{
         status: 200,
         headers: [
           {"anthropic-ratelimit-unified-5h-status", "allowed"},
           {"anthropic-ratelimit-unified-5h-utilization", "0.42"},
           {"anthropic-ratelimit-unified-5h-reset", "1777032600"},
           {"anthropic-ratelimit-unified-7d-status", "allowed"},
           {"anthropic-ratelimit-unified-7d-utilization", "0.01"},
           {"anthropic-ratelimit-unified-7d-reset", "1777510800"}
         ]
       }}
    end

    config =
      ProviderConfig.new(%{
        kind: "claude_code",
        options: Adapter.finalize_options(%{"credential_ref" => "credential://claude_code/primary"})
      })

    workspace = temp_workspace!("quota")

    start_result =
      SymphonyElixir.AgentProvider.start_session(workspace,
        agent_provider_config: config,
        run_id: "run-quota",
        agent_quota_preflight: :required,
        claude_rate_limit_req_fun: req_fun
      )

    case start_result do
      {:ok, session} -> assert :ok = SymphonyElixir.AgentProvider.stop_session(session, run_id: "run-quota")
      {:error, _reason} -> :ok
    end

    assert_received {:quota_request, payload, headers}
    assert payload["system"] =~ "Claude Code"
    assert {"authorization", "Bearer oauth-secret"} in headers

    assert {:ok, updated} = Store.get("claude_code", "primary")
    assert updated.latest_quota["session"]["remaining"] == 58
    assert updated.latest_quota["weekly"]["remaining"] == 99
  end

  test "RateLimitProbe reports missing headers distinctly" do
    assert {:error, :empty_rate_limit_headers} =
             RateLimitProbe.rate_limits_from_response([{"content-type", "application/json"}])
  end

  defp enable_credentials!(store_root, overrides \\ []) do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge(
        [
          agent_credentials_enabled: true,
          agent_credentials_store_root: store_root,
          agent_credentials_exhausted_cooldown_ms: 60_000
        ],
        overrides
      )
    )
  end

  defp temp_store_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-claude-credential-quota-#{suffix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp temp_workspace!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-claude-credential-quota-workspace-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
