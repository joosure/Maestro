defmodule SymphonyElixir.Agent.Quota.PollerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.Agent.Quota.Poller

  test "poll_now probes managed provider accounts through provider callbacks" do
    store_root = temp_store_root!("poller")

    write_workflow_file!(
      Workflow.workflow_file_path(),
      agent_credentials_enabled: true,
      agent_credentials_store_root: store_root,
      agent_quota_poller_enabled: true,
      agent_quota_poll_interval_ms: 60_000,
      agent_quota_poll_providers: ["claude_code"]
    )

    {:ok, account} =
      Store.create_or_update("claude_code", "primary", email: "primary@example.com")

    File.write!(account.secret_file, "oauth-secret\n")

    parent = self()

    req_fun = fn _payload, headers ->
      send(parent, {:poll_probe, headers})

      {:ok,
       %{
         status: 200,
         headers: [
           {"anthropic-ratelimit-unified-5h-status", "allowed"},
           {"anthropic-ratelimit-unified-5h-utilization", "0.25"},
           {"anthropic-ratelimit-unified-5h-reset", "1777032600"}
         ]
       }}
    end

    pid =
      start_supervised!({Poller, name: {:global, {__MODULE__, :agent_quota_poller, System.unique_integer([:positive])}}, probe_opts: [claude_rate_limit_req_fun: req_fun]})

    Poller.poll_now(pid)
    :sys.get_state(pid)

    assert_received {:poll_probe, headers}
    assert {"authorization", "Bearer oauth-secret"} in headers

    assert {:ok, updated} = Store.get("claude_code", "primary")
    assert updated.latest_quota["session"]["remaining"] == 75
  end

  defp temp_store_root!(suffix) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-agent-quota-poller-#{suffix}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
