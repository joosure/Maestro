defmodule SymphonyElixir.Agent.Credential.Store.Leases do
  @moduledoc false

  require Logger

  alias SymphonyElixir.Agent.Credential.Lease
  alias SymphonyElixir.Agent.Credential.Store.{Files, Normalization, Paths, Selection, State}

  @spec acquire(map(), String.t(), keyword(), map()) :: {:ok, Lease.t()} | {:error, term()}
  def acquire(account, credential_ref, opts, settings)
      when is_map(account) and is_binary(credential_ref) and is_list(opts) do
    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      now = DateTime.utc_now()
      expires_at = DateTime.add(now, settings.default_ttl_ms, :millisecond)

      active_leases =
        state
        |> Map.get("active_leases", %{})
        |> prune_inactive_leases(account, now, settings)

      if map_size(active_leases) >= settings.max_concurrent_leases_per_account do
        log_concurrency_exhausted(account, active_leases, settings)
        {:error, {:credential_account_concurrency_exhausted, account.id}}
      else
        lease =
          Lease.new(%{
            id: lease_id(account, opts),
            provider_kind: account.agent_provider_kind,
            credential_ref_summary: credential_ref,
            account_id: account.id,
            expires_at: expires_at,
            metadata: %{
              store_managed: true,
              account: account,
              run_id: Keyword.get(opts, :run_id),
              issue_id: Keyword.get(opts, :issue_id),
              worker_host: Selection.worker_host(opts)
            }
          })

        active_leases =
          Map.put(active_leases, lease.id, %{
            "run_id" => Keyword.get(opts, :run_id),
            "worker_host" => Selection.worker_host(opts),
            "acquired_at" => DateTime.to_iso8601(now),
            "expires_at" => DateTime.to_iso8601(expires_at),
            "owner_node" => Atom.to_string(node()),
            "owner_pid" => opts |> Keyword.get(:credential_lease_owner_pid, self()) |> owner_pid_string()
          })

        state =
          state
          |> Map.put("active_leases", active_leases)
          |> Map.put("updated_at", Normalization.now_iso())

        :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
        {:ok, lease}
      end
    end
  end

  @spec release(map(), Lease.t()) :: :ok | {:error, term()}
  def release(account, %Lease{} = lease) when is_map(account) do
    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      state =
        state
        |> State.release_lease(lease.id)

      Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
    end
  end

  @spec list(map(), map()) :: {:ok, [map()]} | {:error, term()}
  def list(account, settings) when is_map(account) and is_map(settings) do
    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      now = DateTime.utc_now()
      active_leases = prune_inactive_leases(Map.get(state, "active_leases", %{}), account, now, settings)

      if active_leases != Map.get(state, "active_leases", %{}) do
        write_active_leases(account, state, active_leases)
      end

      {:ok, lease_summaries(account, active_leases)}
    end
  end

  @spec release_id(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def release_id(account, lease_id) when is_map(account) and is_binary(lease_id) do
    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      active_leases = Map.get(state, "active_leases", %{})

      if Map.has_key?(active_leases, lease_id) do
        state = State.release_lease(state, lease_id)
        :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
        {:ok, lease_summary(account, lease_id, Map.fetch!(active_leases, lease_id))}
      else
        {:error, {:credential_lease_not_found, account.agent_provider_kind, account.id, lease_id}}
      end
    end
  end

  defp lease_id(account, opts) do
    base =
      opts
      |> Keyword.get(:run_id)
      |> case do
        run_id when is_binary(run_id) and run_id != "" -> run_id
        _run_id -> Integer.to_string(System.unique_integer([:positive]))
      end

    "agent-credential-" <> account.agent_provider_kind <> "-" <> account.id <> "-" <> base
  end

  defp owner_pid_string(pid) when is_pid(pid), do: pid |> :erlang.pid_to_list() |> List.to_string()
  defp owner_pid_string(_pid), do: self() |> :erlang.pid_to_list() |> List.to_string()

  defp prune_inactive_leases(active_leases, account, now, settings) when is_map(active_leases) do
    {kept, pruned} =
      State.prune_inactive_leases(active_leases, now, ownerless_stale_recovery_after_ms: settings.lease_timeout_ms)

    log_pruned_leases(account, pruned)
    kept
  end

  defp write_active_leases(account, state, active_leases) do
    state
    |> Map.put("active_leases", active_leases)
    |> Map.put("updated_at", Normalization.now_iso())
    |> then(&Files.write_json(Paths.state_path(account.account_dir), &1, Files.secret_mode()))
  end

  defp lease_summaries(account, active_leases) do
    active_leases
    |> Enum.map(fn {lease_id, lease} -> lease_summary(account, lease_id, lease) end)
    |> Enum.sort_by(&{&1.provider_kind, &1.account_id, &1.lease_id})
  end

  defp lease_summary(account, lease_id, lease) when is_map(lease) do
    %{
      provider_kind: account.agent_provider_kind,
      account_id: account.id,
      lease_id: lease_id,
      run_id: Map.get(lease, "run_id"),
      worker_host: Map.get(lease, "worker_host"),
      acquired_at: Map.get(lease, "acquired_at"),
      expires_at: Map.get(lease, "expires_at"),
      owner_node: Map.get(lease, "owner_node"),
      owner_pid: Map.get(lease, "owner_pid")
    }
  end

  defp log_pruned_leases(_account, []), do: :ok

  defp log_pruned_leases(account, pruned) do
    Enum.each(pruned, fn lease ->
      Logger.info(
        "agent_credential_lease_pruned provider=#{account.agent_provider_kind} account=#{account.id} lease_id=#{lease.lease_id} reason=#{lease.reason} run_id=#{inspect(lease.run_id)} worker_host=#{inspect(lease.worker_host)} acquired_at=#{inspect(lease.acquired_at)} expires_at=#{inspect(lease.expires_at)} owner_node=#{inspect(lease.owner_node)} owner_pid=#{inspect(lease.owner_pid)}"
      )
    end)
  end

  defp log_concurrency_exhausted(account, active_leases, settings) do
    lease_ids = active_leases |> Map.keys() |> Enum.sort()

    Logger.warning(
      "agent_credential_lease_concurrency_exhausted provider=#{account.agent_provider_kind} account=#{account.id} active_lease_count=#{map_size(active_leases)} max_concurrent_leases_per_account=#{settings.max_concurrent_leases_per_account} lease_ids=#{inspect(lease_ids)}"
    )
  end
end
