defmodule SymphonyWorkerDaemon.SimulatedProviderTurnTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Credential.Store
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.{EventSummary, Session, TurnResult}
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyWorkerDaemon.{Api, CapacityManager}
  alias SymphonyWorkerDaemon.Session

  @provider_kind "worker_daemon_simulated"
  @managed_token "managed-secret"

  defmodule SimulatedProviderAdapter do
    @behaviour SymphonyElixir.AgentProvider.Adapter

    alias SymphonyElixir.Agent.Credential.{Lease, Material}
    alias SymphonyElixir.Agent.Quota.Snapshot
    alias SymphonyElixir.Agent.Runtime.{CommandSpec, Environment, Handle}
    alias SymphonyElixir.AgentProvider.{Config, EventSummary, Session, TurnResult}

    @provider_kind "worker_daemon_simulated"

    def kind, do: @provider_kind
    def defaults, do: %{}
    def validate_options(_options), do: :ok
    def finalize_options(options), do: options
    def validate_config(%Config{}), do: :ok

    def capabilities do
      [
        "agent.turn.run",
        "agent.session.stateful",
        "agent.runtime.remote_worker",
        "agent.credentials.managed",
        "agent.quota.probe"
      ]
    end

    def prepare_workspace(%Config{}, _workspace, _opts \\ []), do: :ok

    def materialize_credential(%Config{} = config, %Lease{} = lease, opts) do
      send(self(), {:simulated_credential_materialized, config.kind, lease.account_id, Keyword.get(opts, :run_id)})

      {:ok,
       Material.new(%{
         env: %{"MANAGED_TOKEN" => "managed-secret"},
         summary: %{credential_kind: "simulated_profile", account_id_summary: lease.account_id}
       })}
    end

    def quota_probe(%Config{} = config, %Lease{} = lease, opts) do
      send(self(), {:simulated_quota_probe, config.kind, lease.account_id, Keyword.get(opts, :run_id)})

      {:ok,
       Snapshot.new(%{
         provider_kind: config.kind,
         account_id_summary: lease.account_id,
         status: :healthy,
         remaining: 99,
         limit: 100,
         details: %{
           "rate_limits" => %{
             "session" => %{"limit" => 100, "remaining" => 99}
           }
         }
       })}
    end

    def quota_probe(%Config{} = config, nil, opts) do
      send(self(), {:simulated_quota_probe, config.kind, nil, Keyword.get(opts, :run_id)})
      {:ok, Snapshot.new(provider_kind: config.kind, status: :healthy, remaining: 99, limit: 100)}
    end

    def start_session(%Config{} = config, workspace, opts \\ []) do
      target = Keyword.fetch!(opts, :agent_runtime_target)
      command_argv = Map.fetch!(config.options, "command_argv")

      with {:ok, env} <- Environment.current_env(config.kind, %{}, opts),
           {:ok, handle} <-
             target.executor.start(
               CommandSpec.new(argv: command_argv, env: env, cwd: workspace),
               target,
               opts
             ) do
        send(self(), {:simulated_start_session, config.kind, target.placement, Keyword.get(opts, :run_id)})

        {:ok,
         Session.new(%{
           agent_provider_kind: config.kind,
           provider_state: %{handle: handle},
           session_id: handle.session_id,
           thread_id: "simulated-thread",
           workspace: workspace,
           metadata:
             Handle.safe_metadata(handle)
             |> Map.merge(%{
               worker_placement: Atom.to_string(target.placement),
               credential_materialized: true,
               quota_preflight: "required"
             })
         })}
      end
    end

    def run_turn(%Config{}, %Session{provider_state: %{handle: handle}}, prompt, _issue, _opts \\ []) do
      if Handle.command(handle, prompt <> "\n") do
        {:ok, TurnResult.new(session_id: handle.session_id, thread_id: "simulated-thread", turn_id: "simulated-turn")}
      else
        {:error, :simulated_provider_input_failed}
      end
    end

    def stop_session(%Config{}, %Session{provider_state: %{handle: handle}}, opts \\ []) do
      Handle.close(handle, opts)
    end

    def session_stop_options(%Config{}, _result, issue), do: [issue: issue]
    def failed_session_stop_options(%Config{}, issue, error), do: [issue: issue, extra: %{error: error}]
    def summarize_message(message), do: EventSummary.from_term(message, provider_kind: @provider_kind)
    def session_log_event?(_component, _event), do: false
    def workspace_automation_destination_dir, do: ".worker-daemon-simulated"
  end

  test "simulates credential, quota, and provider turn through worker_daemon mode" do
    Application.put_env(:symphony_elixir, :agent_provider_adapters, %{@provider_kind => SimulatedProviderAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :agent_provider_adapters)
    end)

    elixir_path = System.find_executable("elixir") || flunk("elixir executable is required")
    workspace = tmp_dir!("simulated-provider-turn")
    store_root = tmp_dir!("simulated-provider-credentials")
    daemon_port = free_port!()
    token = "simulated-provider-daemon-token"
    ledger = unique_name("Session.Ledger")
    registry = unique_name("Registry")
    capacity = unique_name("Capacity")
    supervisor = unique_name("Session.Supervisor")
    credential_opts = credential_opts(store_root)

    {:ok, account} =
      Store.create_or_update(
        @provider_kind,
        "primary",
        [credential_kind: "simulated_profile", email: "simulated@example.com"],
        credential_opts
      )

    File.write!(account.secret_file, "synthetic-secret\n")

    start_supervised!({Session.Ledger, name: ledger})
    start_supervised!({Registry, keys: :unique, name: registry})
    start_supervised!({CapacityManager, name: capacity, max_sessions: 1})
    start_supervised!({Session.Supervisor, name: supervisor, session_ledger: ledger})

    start_supervised!(
      {Bandit,
       plug:
         {Api,
          [
            token: token,
            session_ledger: ledger,
            registry: registry,
            capacity_manager: capacity,
            session_supervisor: supervisor,
            workspace_roots: [workspace],
            worker_id: "simulated-provider-worker",
            daemon_instance_id: "simulated-provider-daemon",
            allowed_executables: [elixir_path]
          ]},
       scheme: :http,
       ip: {127, 0, 0, 1},
       port: daemon_port}
    )

    config =
      ProviderConfig.new(%{
        kind: @provider_kind,
        options: %{
          "credential_ref" => "credential://#{@provider_kind}/primary",
          "command_argv" => [elixir_path, "-e", simulated_provider_script()]
        }
      })

    assert {:ok, session} =
             AgentProvider.start_session(
               workspace,
               [
                 agent_provider_config: config,
                 agent_runtime_placement: :worker_daemon,
                 worker_pool: "simulated-worker-pool",
                 worker_daemon_endpoint: "http://127.0.0.1:#{daemon_port}",
                 worker_daemon_token: token,
                 worker_daemon_timeout_ms: 30_000,
                 agent_quota_preflight: :required,
                 run_id: "run-worker-daemon-simulated"
               ] ++ credential_opts
             )

    assert_received {:simulated_credential_materialized, @provider_kind, "primary", "run-worker-daemon-simulated"}
    assert_received {:simulated_quota_probe, @provider_kind, "primary", "run-worker-daemon-simulated"}
    assert_received {:simulated_start_session, @provider_kind, :worker_daemon, "run-worker-daemon-simulated"}

    assert session.agent_credential_lease.id != nil
    assert session.metadata.worker_placement == "worker_daemon"
    assert session.metadata.worker_daemon_worker_id == "simulated-provider-worker"
    assert session.metadata.quota_preflight == "required"

    handle = session.provider_state.handle
    assert %WorkerDaemon.SessionHandle{} = handle
    assert WorkerDaemon.Client.session_status(handle) == {:ok, "running"}

    events = wait_for_provider_events!(handle)
    assert Enum.any?(events, &(event_data(&1) =~ "simulated-provider-ready"))
    assert Enum.any?(events, &(event_data(&1) =~ "credential-env-present"))

    assert {:ok, turn_result} =
             AgentProvider.run_turn(session, "simulated prompt", %{
               id: "issue-worker-daemon-simulated",
               identifier: "WD-SIM",
               title: "Worker daemon simulated provider turn"
             })

    assert turn_result.status == :completed
    assert turn_result.session_id == handle.session_id

    assert :ok = AgentProvider.stop_session(session, run_id: "run-worker-daemon-simulated")
    assert {:ok, account_after_stop} = Store.get(@provider_kind, "primary", credential_opts)
    assert account_after_stop.state == "healthy"
    assert account_after_stop.latest_quota["session"]["remaining"] == 99
    assert account_after_stop.token_totals["total"]["total_tokens"] == 0

    events = EventStore.recent_events(limit: 20)
    assert Enum.any?(events, &(&1["event"] == "agent_credential_lease_acquired" and &1["agent_provider_kind"] == @provider_kind))
    assert Enum.any?(events, &(&1["event"] == "agent_quota_probe_completed" and &1["quota_status"] == "healthy"))
    assert Enum.any?(events, &(&1["event"] == "agent_session_started" and &1["agent_provider_kind"] == @provider_kind))

    refute inspect(events) =~ @managed_token
  end

  defp simulated_provider_script do
    """
    IO.puts("simulated-provider-ready")

    if System.get_env("MANAGED_TOKEN") == "managed-secret" do
      IO.puts("credential-env-present")
    else
      IO.puts("credential-env-missing")
    end

    Process.sleep(:infinity)
    """
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-worker-daemon-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp credential_opts(store_root) do
    [
      agent_credentials: %{
        enabled: true,
        store_root: store_root,
        exhausted_cooldown_ms: 60_000
      }
    ]
  end

  defp free_port! do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  @process_names %{
    "Session.Ledger" => __MODULE__.SessionLedger,
    "Registry" => __MODULE__.Registry,
    "Capacity" => __MODULE__.Capacity,
    "Session.Supervisor" => __MODULE__.SessionSupervisor
  }

  defp unique_name(prefix), do: Map.fetch!(@process_names, prefix)

  defp wait_for_provider_events!(handle, attempts_left \\ 100)

  defp wait_for_provider_events!(handle, attempts_left) when attempts_left > 0 do
    case WorkerDaemon.Client.session_events(handle) do
      {:ok, events} ->
        if provider_startup_events_complete?(events) do
          events
        else
          Process.sleep(50)
          wait_for_provider_events!(handle, attempts_left - 1)
        end

      {:error, _reason} ->
        Process.sleep(50)
        wait_for_provider_events!(handle, attempts_left - 1)
    end
  end

  defp wait_for_provider_events!(handle, 0) do
    assert {:ok, events} = WorkerDaemon.Client.session_events(handle)
    events
  end

  defp event_data(event) when is_map(event), do: Map.get(event, :data) || Map.get(event, "data") || ""

  defp provider_startup_events_complete?(events) when is_list(events) do
    Enum.any?(events, &(event_data(&1) =~ "simulated-provider-ready")) and
      Enum.any?(events, &(event_data(&1) =~ "credential-env-present"))
  end
end
