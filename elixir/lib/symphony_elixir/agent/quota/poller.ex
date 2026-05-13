defmodule SymphonyElixir.Agent.Quota.Poller do
  @moduledoc false

  use GenServer

  require Logger

  alias SymphonyElixir.Agent.Credential.Store, as: CredentialStore
  alias SymphonyElixir.Agent.Quota.Snapshot
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.AgentProvider.Config, as: ProviderConfig
  alias SymphonyElixir.AgentProvider.Registry
  alias SymphonyElixir.Config
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @quota_capability "agent.quota.probe"
  @credential_capability "agent.credentials.managed"
  @startup_delay_ms 5_000
  @idle_reschedule_ms 300_000

  @type option :: {:name, GenServer.name()} | {:probe_opts, keyword()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec poll_now(GenServer.name()) :: :ok
  def poll_now(server \\ __MODULE__) do
    GenServer.cast(server, :poll_now)
  end

  @impl true
  def init(opts) do
    state = %{
      probe_opts: Keyword.get(opts, :probe_opts, []),
      timer_ref: nil
    }

    {:ok, schedule_next(state, @startup_delay_ms)}
  end

  @impl true
  def handle_info(:poll, state), do: {:noreply, run_poll_cycle(state)}

  @impl true
  def handle_cast(:poll_now, state), do: {:noreply, run_poll_cycle(state)}

  defp run_poll_cycle(state) do
    settings = quota_settings()

    if settings.poller_enabled and CredentialStore.enabled?() do
      probe_all(state, settings)
      schedule_next(state, settings.poll_interval_ms)
    else
      schedule_next(state, @idle_reschedule_ms)
    end
  end

  defp probe_all(state, settings) do
    settings
    |> poll_providers()
    |> Enum.each(&probe_provider(&1, state))
  end

  defp poll_providers(%{poll_providers: providers}) when is_list(providers) and providers != [] do
    Enum.uniq(providers)
  end

  defp poll_providers(_settings) do
    Registry.adapters()
    |> Enum.filter(fn {_kind, adapter} -> provider_supports_quota?(adapter) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp probe_provider(provider_kind, state) do
    case {AgentProvider.adapter_for(provider_kind), CredentialStore.list(provider_kind)} do
      {adapter, {:ok, accounts}} when is_atom(adapter) ->
        accounts
        |> Enum.filter(&probeable?/1)
        |> Enum.each(&probe_account(provider_kind, adapter, &1, state))

      _other ->
        :ok
    end
  end

  defp probe_account(provider_kind, adapter, account, state) do
    config = ProviderConfig.new(%{kind: provider_kind, options: adapter.finalize_options(%{"credential_ref" => CredentialStore.credential_ref(account)})})
    opts = Keyword.merge([run_id: "agent-quota-poller", agent_credentials: CredentialStore.settings()], state.probe_opts)

    ObsLogger.emit(:info, :agent_quota_probe_started, %{
      component: "agent_quota",
      operation: "poll",
      preflight: "poller",
      status: "started",
      agent_provider_kind: provider_kind
    })

    result =
      with {:ok, lease} <- CredentialStore.acquire(provider_kind, CredentialStore.credential_ref(account), opts),
           {:ok, material} <- materialize(adapter, config, lease, opts),
           {:ok, snapshot} <- probe(adapter, config, lease, Keyword.put(opts, :agent_credential_material, material)) do
        CredentialStore.record_quota(lease, snapshot_rate_limits(snapshot), opts)
        CredentialStore.release(lease, opts)
        {:ok, snapshot}
      else
        {:error, reason} = error ->
          Logger.warning("Agent quota poll failed for #{provider_kind}:#{account.id}: #{inspect(reason)}")
          error

        :unsupported ->
          :unsupported
      end

    emit_poll_result(provider_kind, result)
  end

  defp materialize(adapter, config, lease, opts) do
    if provider_supports_credentials?(adapter) and function_exported?(adapter, :materialize_credential, 3) do
      adapter.materialize_credential(config, lease, opts)
    else
      {:error, :managed_credentials_unsupported}
    end
  end

  defp probe(adapter, config, lease, opts) do
    case adapter.quota_probe(config, lease, opts) do
      {:ok, %Snapshot{} = snapshot} -> {:ok, snapshot}
      {:ok, snapshot} when is_map(snapshot) -> {:ok, Snapshot.new(snapshot)}
      other -> other
    end
  end

  defp snapshot_rate_limits(%Snapshot{details: %{"rate_limits" => rate_limits}}) when is_map(rate_limits), do: rate_limits
  defp snapshot_rate_limits(%Snapshot{details: %{rate_limits: rate_limits}}) when is_map(rate_limits), do: rate_limits
  defp snapshot_rate_limits(_snapshot), do: nil

  defp emit_poll_result(provider_kind, {:ok, %Snapshot{} = snapshot}) do
    ObsLogger.emit(:info, :agent_quota_probe_completed, %{
      component: "agent_quota",
      operation: "poll",
      preflight: "poller",
      status: "completed",
      agent_provider_kind: provider_kind,
      quota_status: Atom.to_string(snapshot.status)
    })
  end

  defp emit_poll_result(provider_kind, :unsupported) do
    ObsLogger.emit(:info, :agent_quota_probe_completed, %{
      component: "agent_quota",
      operation: "poll",
      preflight: "poller",
      status: "completed",
      agent_provider_kind: provider_kind,
      quota_status: "unsupported"
    })
  end

  defp emit_poll_result(provider_kind, {:error, reason}) do
    ObsLogger.emit(:error, :agent_quota_probe_failed, %{
      component: "agent_quota",
      operation: "poll",
      preflight: "poller",
      status: "failed",
      agent_provider_kind: provider_kind,
      quota_status: "unknown",
      error: inspect(reason)
    })
  end

  defp probeable?(%{enabled: false}), do: false
  defp probeable?(%{state: state}) when state in ["disabled", "paused", "exhausted"], do: false
  defp probeable?(_account), do: true

  defp provider_supports_quota?(adapter) when is_atom(adapter) do
    @quota_capability in adapter.capabilities()
  rescue
    _error -> false
  end

  defp provider_supports_credentials?(adapter) when is_atom(adapter) do
    @credential_capability in adapter.capabilities()
  rescue
    _error -> false
  end

  defp schedule_next(state, delay_ms) do
    cancel_timer(state.timer_ref)
    timer_ref = Process.send_after(self(), :poll, max(delay_ms, 1_000))
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp quota_settings do
    Config.agent_quota_settings()
  rescue
    _error ->
      %{poller_enabled: false, poll_interval_ms: @idle_reschedule_ms, poll_providers: []}
  end
end
