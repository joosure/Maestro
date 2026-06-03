defmodule SymphonyElixir.Agent.Credential.StoreTest do
  use SymphonyElixir.TestSupport

  import ExUnit.CaptureLog

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.Config.Schema.Credentials

  test "store settings use credential schema defaults" do
    assert Store.settings(%{}) == Credentials.defaults()
  end

  test "file-backed store leases and releases a provider account" do
    store_root = temp_store_root!("lease")
    enable_credentials!(store_root)

    {:ok, account} =
      Store.create_or_update("claude_code", "primary", email: "primary@example.com")

    File.write!(account.secret_file, "oauth-token\n")

    assert {:ok, lease} =
             Store.acquire("claude_code", "credential://claude_code/primary",
               run_id: "run-lease",
               worker_host: nil
             )

    assert lease.provider_kind == "claude_code"
    assert lease.account_id == "primary"
    assert lease.metadata[:account].credential_kind == "claude_oauth_token"

    assert {:error, {:credential_account_unavailable, "primary", "account concurrency limit reached"}} =
             Store.acquire("claude_code", "credential://claude_code/primary", run_id: "run-second")

    assert :ok = Store.release(lease)

    assert {:ok, next_lease} =
             Store.acquire("claude_code", "credential://claude_code/primary", run_id: "run-next")

    assert :ok = Store.release(next_lease)
  end

  test "acquire prunes stale local owner leases before applying account concurrency" do
    store_root = temp_store_root!("stale-owner")
    enable_credentials!(store_root)

    {:ok, account} = Store.create_or_update("opencode", "zai", env_name: "ZAI_API_KEY")
    File.write!(account.secret_file, "zai-token\n")

    stale_owner = spawn(fn -> :ok end)
    ref = Process.monitor(stale_owner)
    assert_receive {:DOWN, ^ref, :process, ^stale_owner, :normal}

    assert {:ok, stale_lease} =
             Store.acquire("opencode", "credential://opencode/zai",
               run_id: "run-stale",
               credential_lease_owner_pid: stale_owner
             )

    log =
      capture_log(fn ->
        assert {:ok, next_lease} = Store.acquire("opencode", "credential://opencode/zai", run_id: "run-next")
        assert next_lease.account_id == "zai"
        assert :ok = Store.release(next_lease)
      end)

    assert log =~ "agent_credential_lease_pruned"
    assert log =~ "reason=stale_owner"
    assert log =~ stale_lease.id
  end

  test "acquire prunes ownerless stale leases after lease timeout" do
    store_root = temp_store_root!("ownerless-stale")

    enable_credentials!(store_root,
      agent_credentials_lease_timeout_ms: 10
    )

    {:ok, account} = Store.create_or_update("opencode", "zai", env_name: "ZAI_API_KEY")
    File.write!(account.secret_file, "zai-token\n")

    now = DateTime.utc_now()
    ownerless_lease_id = "agent-credential-opencode-zai-ownerless"

    state = %{
      "active_leases" => %{
        ownerless_lease_id => %{
          "run_id" => "run-ownerless",
          "worker_host" => nil,
          "acquired_at" => now |> DateTime.add(-1_000, :millisecond) |> DateTime.to_iso8601(),
          "expires_at" => now |> DateTime.add(3_600_000, :millisecond) |> DateTime.to_iso8601()
        }
      }
    }

    File.write!(Path.join(account.account_dir, "state.json"), Jason.encode!(state))

    log =
      capture_log(fn ->
        assert {:ok, next_lease} = Store.acquire("opencode", "credential://opencode/zai", run_id: "run-next")
        assert next_lease.account_id == "zai"
        assert :ok = Store.release(next_lease)
      end)

    assert log =~ "agent_credential_lease_pruned"
    assert log =~ "reason=stale_ownerless"
    assert log =~ ownerless_lease_id
  end

  test "operator lease APIs list and release active leases without editing state files" do
    store_root = temp_store_root!("lease-api")
    opts = store_opts(store_root)

    {:ok, account} = Store.create_or_update("opencode", "zai", [env_name: "ZAI_API_KEY"], opts)
    File.write!(account.secret_file, "zai-token\n")

    assert {:ok, lease} =
             Store.acquire("opencode", "credential://opencode/zai",
               run_id: "run-list",
               agent_credentials: opts.agent.credentials
             )

    assert {:ok, [listed]} = Store.list_leases("opencode", "zai", opts)
    assert listed.provider_kind == "opencode"
    assert listed.account_id == "zai"
    assert listed.lease_id == lease.id
    assert listed.run_id == "run-list"
    assert is_binary(listed.owner_pid)

    assert {:ok, released} = Store.release_lease("opencode", "zai", lease.id, opts)
    assert released.lease_id == lease.id
    assert {:ok, []} = Store.list_leases("opencode", "zai", opts)
  end

  test "least-usage pool selection avoids accounts near session or weekly quota exhaustion" do
    store_root = temp_store_root!("least-usage")

    enable_credentials!(store_root,
      agent_credentials_rotation_strategy: "least_usage",
      agent_credentials_max_concurrent_leases_per_account: 2
    )

    reset_at = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_iso8601()

    {:ok, a} = Store.create_or_update("claude_code", "a", [])
    {:ok, b} = Store.create_or_update("claude_code", "b", [])

    Store.record_quota(a, %{
      "limit_id" => "anthropic_oauth",
      "session" => %{"limit" => 100, "remaining" => 20, "reset_at" => reset_at},
      "weekly" => %{"limit" => 1_000, "remaining" => 900, "reset_at" => reset_at}
    })

    Store.record_quota(b, %{
      "limit_id" => "anthropic_oauth",
      "session" => %{"limit" => 100, "remaining" => 90, "reset_at" => reset_at},
      "weekly" => %{"limit" => 1_000, "remaining" => 500, "reset_at" => reset_at}
    })

    assert {:ok, lease} = Store.acquire("claude_code", "credential://claude_code/*", run_id: "run-pool")
    assert lease.account_id == "b"
  end

  test "usage recording updates selected account token totals and quota periods" do
    store_root = temp_store_root!("usage")
    enable_credentials!(store_root)
    reset_at = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.to_iso8601()

    {:ok, account} = Store.create_or_update("claude_code", "usage", [])

    Store.record_quota(account, %{
      "limit_id" => "anthropic_oauth",
      "session" => %{"limit" => 100, "remaining" => 50, "reset_at" => reset_at}
    })

    assert {:ok, lease} = Store.acquire("claude_code", "credential://claude_code/usage", run_id: "run-usage")
    Store.record_usage(lease, %{input_tokens: 3, output_tokens: 4, total_tokens: 7})

    assert {:ok, updated} = Store.get("claude_code", "usage")
    assert updated.token_totals["total"]["total_tokens"] == 7
    assert updated.rate_limit_periods["session"]["total_tokens"] == 7
  end

  test "operator lifecycle APIs update account availability without provider-specific paths" do
    store_root = temp_store_root!("lifecycle")
    opts = store_opts(store_root)

    assert {:ok, account} =
             Store.create_or_update("claude_code", "operator", [email: "ops@example.com"], opts)

    assert account.auth_dir == Path.join(account.account_dir, "auth")
    assert account.secret_file == Path.join(account.account_dir, "secret")

    assert {:ok, paused} = Store.pause("claude_code", "operator", [reason: "rotation"], opts)
    assert paused.state == "paused"
    assert paused.failure_reason == "rotation"

    assert {:ok, disabled} = Store.disable("claude_code", "operator", opts)
    assert disabled.state == "disabled"

    assert {:ok, enabled} = Store.enable("claude_code", "operator", opts)
    assert enabled.state == "unknown"

    assert {:ok, resumed} = Store.resume("claude_code", "operator", opts)
    assert resumed.state == "unknown"
    assert resumed.paused_until == nil

    assert {:ok, [listed]} = Store.list_all(opts)
    assert listed.agent_provider_kind == "claude_code"

    summary = Store.account_summary(listed)
    assert summary.agent_provider_kind == "claude_code"
    assert summary.usage_periods_csv == Path.join(listed.account_dir, "usage_periods.csv")

    assert :ok = Store.remove("claude_code", "operator", opts)
    assert {:ok, []} = Store.list("claude_code", opts)
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
        "symphony-agent-credential-store-#{suffix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    root
  end

  defp store_opts(store_root) do
    %{agent: %{credentials: %{enabled: true, store_root: store_root, exhausted_cooldown_ms: 60_000}}}
  end
end
