defmodule SymphonyElixir.Agent.Credential.Store.Leases do
  @moduledoc false

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
        |> State.prune_expired_leases(now)

      if map_size(active_leases) >= settings.max_concurrent_leases_per_account do
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
            "expires_at" => DateTime.to_iso8601(expires_at)
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
end
