defmodule SymphonyElixir.Agent.Credential.Store do
  @moduledoc false

  require Logger

  alias SymphonyElixir.Agent.Credential.Lease

  alias SymphonyElixir.Agent.Credential.Store.{
    AccountRecord,
    Files,
    Leases,
    Normalization,
    Paths,
    RateLimits,
    Selection,
    Settings,
    State,
    Usage
  }

  @type settings :: Settings.t()
  @type account :: map()

  @spec settings(keyword() | map() | nil) :: settings()
  def settings(opts \\ nil), do: Settings.resolve(opts)

  @spec enabled?(keyword() | map() | nil) :: boolean()
  def enabled?(opts \\ nil), do: Settings.enabled?(opts)

  @spec create_or_update(String.t(), String.t(), keyword() | map(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def create_or_update(provider_kind, id, attrs \\ [], opts \\ nil)
      when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)
    id = Normalization.normalize_id!(id)
    attrs = Normalization.normalize_attrs(attrs)
    account_dir = Paths.account_dir(provider_kind, id, settings)

    with :ok <- Files.ensure_account_dirs(account_dir),
         {:ok, existing} <- Files.read_json(Paths.metadata_path(account_dir), %{}),
         metadata <- AccountRecord.merge_metadata(existing, provider_kind, id, attrs),
         :ok <- Files.write_json(Paths.metadata_path(account_dir), metadata, Files.secret_mode()),
         {:ok, state} <- Files.read_json(Paths.state_path(account_dir), State.default()),
         :ok <-
           Files.write_json(
             Paths.state_path(account_dir),
             Map.merge(State.default(), state),
             Files.secret_mode()
           ) do
      get(provider_kind, id, settings)
    end
  rescue
    error -> {:error, error}
  end

  @spec get(String.t(), String.t(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def get(provider_kind, id, opts \\ nil) when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)
    account_dir = Paths.account_dir(provider_kind, id, settings)

    case load_account_from_dir(provider_kind, account_dir, settings) do
      [account] -> {:ok, account}
      [] -> {:error, :not_found}
    end
  rescue
    error -> {:error, error}
  end

  @spec list(String.t(), keyword() | map() | nil) :: {:ok, [account()]} | {:error, term()}
  def list(provider_kind, opts \\ nil) when is_binary(provider_kind) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)

    accounts =
      provider_kind
      |> Paths.backend_dir(settings)
      |> Paths.account_dirs()
      |> Enum.flat_map(&load_account_from_dir(provider_kind, &1, settings))
      |> Enum.sort_by(& &1.id)

    {:ok, accounts}
  rescue
    error -> {:error, error}
  end

  @spec list_all(keyword() | map() | nil) :: {:ok, [account()]} | {:error, term()}
  def list_all(opts \\ nil) do
    settings = settings(opts)

    accounts =
      settings.store_root
      |> Paths.account_dirs()
      |> Enum.flat_map(fn provider_dir ->
        provider_kind = Path.basename(provider_dir)

        provider_dir
        |> Paths.account_dirs()
        |> Enum.flat_map(&load_account_from_dir(provider_kind, &1, settings))
      end)
      |> Enum.sort_by(&{&1.agent_provider_kind, &1.id})

    {:ok, accounts}
  rescue
    error -> {:error, error}
  end

  @spec credential_ref(account()) :: String.t()
  def credential_ref(%{agent_provider_kind: provider_kind, id: id})
      when is_binary(provider_kind) and is_binary(id) do
    "credential://#{provider_kind}/#{id}"
  end

  @spec acquire(String.t(), String.t(), keyword()) :: {:ok, Lease.t()} | {:error, term()}
  def acquire(provider_kind, credential_ref, opts \\ [])
      when is_binary(provider_kind) and is_binary(credential_ref) and is_list(opts) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)

    with {:ok, selector} <- Selection.parse_credential_ref(provider_kind, credential_ref),
         {:ok, account} <- select_account(provider_kind, selector, opts, settings),
         {:ok, lease} <- Leases.acquire(account, credential_ref, opts, settings) do
      {:ok, lease}
    end
  end

  @spec release(Lease.t(), keyword()) :: :ok | {:error, term()}
  def release(%Lease{} = lease, opts \\ []) when is_list(opts) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{agent_provider_kind: provider_kind, id: id} ->
        with {:ok, account} <- get(provider_kind, id, opts) do
          Leases.release(account, lease)
        end

      _account ->
        :ok
    end
  rescue
    error -> {:error, error}
  end

  @spec list_leases(String.t() | nil, String.t() | nil, keyword() | map() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def list_leases(provider_kind \\ nil, id \\ nil, opts \\ nil)

  def list_leases(nil, nil, opts) do
    settings = settings(opts)

    with {:ok, accounts} <- list_all(opts) do
      list_account_leases(accounts, settings)
    end
  end

  def list_leases(provider_kind, nil, opts) when is_binary(provider_kind) do
    settings = settings(opts)

    with {:ok, accounts} <- list(provider_kind, opts) do
      list_account_leases(accounts, settings)
    end
  end

  def list_leases(provider_kind, id, opts) when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)

    with {:ok, account} <- get(provider_kind, id, opts) do
      Leases.list(account, settings)
    end
  end

  @spec release_lease(String.t(), String.t(), String.t(), keyword() | map() | nil) ::
          {:ok, map()} | {:error, term()}
  def release_lease(provider_kind, id, lease_id, opts \\ nil)
      when is_binary(provider_kind) and is_binary(id) and is_binary(lease_id) do
    with {:ok, account} <- get(provider_kind, id, opts) do
      Leases.release_id(account, lease_id)
    end
  end

  @spec record_quota(Lease.t() | account() | nil, map() | nil, keyword() | map() | nil) :: :ok
  def record_quota(target, rate_limits, opts \\ nil)
  def record_quota(_target, nil, _opts), do: :ok
  def record_quota(nil, _rate_limits, _opts), do: :ok

  def record_quota(%Lease{} = lease, rate_limits, opts) when is_map(rate_limits) do
    lease
    |> account_from_target(opts)
    |> record_quota(rate_limits, opts)
  end

  def record_quota(account, rate_limits, opts) when is_map(account) and is_map(rate_limits) do
    settings = settings(opts)

    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      {state, usage_period_rows} =
        RateLimits.apply_snapshot(state, rate_limits, account, settings)

      :ok = RateLimits.append_usage_period_rows(account, usage_period_rows)
      :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
    end

    :ok
  rescue
    error ->
      Logger.warning("Failed to record agent credential quota snapshot: #{Exception.message(error)}")

      :ok
  end

  @spec record_usage(
          Lease.t() | account() | nil,
          map() | nil,
          DateTime.t() | nil,
          keyword() | map() | nil
        ) :: :ok
  def record_usage(target, token_delta, timestamp \\ nil, opts \\ nil)
  def record_usage(_target, nil, _timestamp, _opts), do: :ok
  def record_usage(nil, _token_delta, _timestamp, _opts), do: :ok

  def record_usage(%Lease{} = lease, token_delta, timestamp, opts) when is_map(token_delta) do
    lease
    |> account_from_target(opts)
    |> record_usage(token_delta, timestamp, opts)
  end

  def record_usage(account, token_delta, timestamp, _opts)
      when is_map(account) and is_map(token_delta) do
    timestamp = timestamp || DateTime.utc_now()

    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      state = Usage.apply_token_delta(state, token_delta, timestamp)
      :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
    end

    :ok
  rescue
    error ->
      Logger.warning("Failed to record agent credential usage: #{Exception.message(error)}")
      :ok
  end

  @spec mark_success(Lease.t() | account() | nil, keyword() | map() | nil) :: :ok
  def mark_success(target, opts \\ nil)
  def mark_success(nil, _opts), do: :ok

  def mark_success(%Lease{} = lease, opts) do
    lease
    |> account_from_target(opts)
    |> mark_success(opts)
  end

  def mark_success(account, _opts) when is_map(account) do
    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      state = State.mark_success(state)
      :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
    end

    :ok
  rescue
    _error -> :ok
  end

  @spec mark_exhausted(Lease.t() | account() | nil, term(), keyword() | map() | nil) :: :ok
  def mark_exhausted(target, reason, opts \\ nil)
  def mark_exhausted(nil, _reason, _opts), do: :ok

  def mark_exhausted(%Lease{} = lease, reason, opts) do
    lease
    |> account_from_target(opts)
    |> mark_exhausted(reason, opts)
  end

  def mark_exhausted(account, reason, opts) when is_map(account) do
    settings = settings(opts)

    with {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      state = State.mark_exhausted(state, reason, settings)
      :ok = Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode())
    end

    :ok
  rescue
    _error -> :ok
  end

  @spec pause(String.t(), String.t(), keyword() | map(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def pause(provider_kind, id, attrs \\ [], opts \\ nil)
      when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)
    attrs = Normalization.normalize_attrs(attrs)

    with {:ok, account} <- get(provider_kind, id, settings),
         {:ok, metadata} <- Files.read_json(Paths.metadata_path(account.account_dir), %{}),
         {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      {metadata, reason} = AccountRecord.pause_metadata(metadata, attrs)
      state = State.pause(state, reason)

      with :ok <-
             Files.write_json(
               Paths.metadata_path(account.account_dir),
               metadata,
               Files.secret_mode()
             ),
           :ok <-
             Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode()) do
        get(provider_kind, id, settings)
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec resume(String.t(), String.t(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def resume(provider_kind, id, opts \\ nil) when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)

    with {:ok, account} <- get(provider_kind, id, settings),
         {:ok, metadata} <- Files.read_json(Paths.metadata_path(account.account_dir), %{}),
         {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      metadata = AccountRecord.resume_metadata(metadata)
      state = State.resume(state)

      with :ok <-
             Files.write_json(
               Paths.metadata_path(account.account_dir),
               metadata,
               Files.secret_mode()
             ),
           :ok <-
             Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode()) do
        get(provider_kind, id, settings)
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec enable(String.t(), String.t(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def enable(provider_kind, id, opts \\ nil), do: set_enabled(provider_kind, id, true, opts)

  @spec disable(String.t(), String.t(), keyword() | map() | nil) ::
          {:ok, account()} | {:error, term()}
  def disable(provider_kind, id, opts \\ nil), do: set_enabled(provider_kind, id, false, opts)

  @spec remove(String.t(), String.t(), keyword() | map() | nil) :: :ok | {:error, term()}
  def remove(provider_kind, id, opts \\ nil) when is_binary(provider_kind) and is_binary(id) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)
    account_dir = Paths.account_dir(provider_kind, Normalization.normalize_id!(id), settings)

    case File.rm_rf(account_dir) do
      {:ok, _removed} -> :ok
      {:error, reason, path} -> {:error, {:remove_credential_account_failed, path, reason}}
    end
  rescue
    error -> {:error, error}
  end

  @spec account_summary(account() | nil) :: map() | nil
  def account_summary(account), do: AccountRecord.summary(account)

  @spec quota_error?(term()) :: boolean()
  def quota_error?(reason), do: RateLimits.quota_error?(reason)

  defp select_account(provider_kind, selector, opts, settings) do
    worker_host = Selection.worker_host(opts)

    case selector do
      {:account, id} ->
        with {:ok, account} <- get(provider_kind, id, settings) do
          case Selection.validate_account_available(account, worker_host, settings) do
            {:ok, account} ->
              {:ok, account}

            {:error, {:credential_account_unavailable, _id, "account concurrency limit reached"} = error} ->
              log_account_concurrency_blocked(account, settings)
              {:error, error}

            error ->
              error
          end
        end

      :pool ->
        with {:ok, accounts} <- list(provider_kind, settings) do
          accounts
          |> Enum.filter(&Selection.account_matches_host?(&1, worker_host))
          |> Selection.select_usable_account(provider_kind, settings)
        end
    end
  end

  defp load_account_from_dir(provider_kind, account_dir, settings) do
    with true <- File.regular?(Paths.metadata_path(account_dir)),
         {:ok, metadata} <- Files.read_json(Paths.metadata_path(account_dir), %{}),
         {:ok, state} <- Files.read_json(Paths.state_path(account_dir), State.default()) do
      [AccountRecord.normalize(provider_kind, account_dir, metadata, state, settings)]
    else
      _result -> []
    end
  end

  defp list_account_leases(accounts, settings) when is_list(accounts) and is_map(settings) do
    accounts
    |> Enum.reduce_while({:ok, []}, fn account, {:ok, acc} ->
      case Leases.list(account, settings) do
        {:ok, leases} -> {:cont, {:ok, leases ++ acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, leases} -> {:ok, Enum.sort_by(leases, &{&1.provider_kind, &1.account_id, &1.lease_id})}
      error -> error
    end
  end

  defp log_account_concurrency_blocked(account, settings) do
    active_leases = Map.get(account, :active_leases, %{})
    lease_ids = active_leases |> Map.keys() |> Enum.sort()

    Logger.warning(
      "agent_credential_account_concurrency_blocked provider=#{account.agent_provider_kind} account=#{account.id} active_lease_count=#{map_size(active_leases)} max_concurrent_leases_per_account=#{settings.max_concurrent_leases_per_account} lease_ids=#{inspect(lease_ids)}"
    )
  end

  defp set_enabled(provider_kind, id, enabled, opts) do
    settings = settings(opts)
    provider_kind = Normalization.normalize_provider_kind!(provider_kind)

    with {:ok, account} <- get(provider_kind, id, settings),
         {:ok, metadata} <- Files.read_json(Paths.metadata_path(account.account_dir), %{}),
         {:ok, state} <- Files.read_json(Paths.state_path(account.account_dir), State.default()) do
      metadata = AccountRecord.set_enabled_metadata(metadata, enabled)
      state = State.set_enabled(state, enabled)

      with :ok <-
             Files.write_json(
               Paths.metadata_path(account.account_dir),
               metadata,
               Files.secret_mode()
             ),
           :ok <-
             Files.write_json(Paths.state_path(account.account_dir), state, Files.secret_mode()) do
        get(provider_kind, id, settings)
      end
    end
  rescue
    error -> {:error, error}
  end

  defp account_from_target(%Lease{} = lease, opts) do
    case lease.metadata[:account] || lease.metadata["account"] do
      %{agent_provider_kind: provider_kind, id: id} -> get(provider_kind, id, opts) |> ok_value()
      account when is_map(account) -> account
      _account -> nil
    end
  end

  defp ok_value({:ok, value}), do: value
  defp ok_value(_result), do: nil
end
