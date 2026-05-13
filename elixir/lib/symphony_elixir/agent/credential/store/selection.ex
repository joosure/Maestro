defmodule SymphonyElixir.Agent.Credential.Store.Selection do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Store.{Files, Normalization, Paths, RateLimits, State}

  @spec parse_credential_ref(String.t(), String.t()) ::
          {:ok, :pool | {:account, String.t()}} | {:error, term()}
  def parse_credential_ref(provider_kind, "credential://" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [selector] when selector in ["", "*"] ->
        {:ok, :pool}

      [^provider_kind, selector] when selector in ["", "*"] ->
        {:ok, :pool}

      [^provider_kind, account_id] ->
        {:ok, {:account, Normalization.normalize_id!(account_id)}}

      [account_id] ->
        {:ok, {:account, Normalization.normalize_id!(account_id)}}

      [other_provider, _account_id] ->
        {:error, {:credential_ref_provider_mismatch, expected: provider_kind, got: other_provider}}
    end
  rescue
    error -> {:error, error}
  end

  def parse_credential_ref(_provider_kind, credential_ref),
    do: {:error, {:unsupported_credential_ref, credential_ref}}

  @spec validate_account_available(map(), String.t() | nil, map()) ::
          {:ok, map()} | {:error, term()}
  def validate_account_available(account, worker_host, settings) do
    cond do
      not account_matches_host?(account, worker_host) ->
        {:error, {:credential_account_unavailable, account.id, "worker host mismatch"}}

      reason = account_unavailable_reason(account, settings) ->
        {:error, {:credential_account_unavailable, account.id, reason}}

      true ->
        {:ok, account}
    end
  end

  @spec select_usable_account([map()], String.t(), map()) :: {:ok, map()} | {:error, term()}
  def select_usable_account([], _provider_kind, %{allow_host_auth_reuse: true}),
    do: {:error, :managed_credential_not_configured}

  def select_usable_account([], provider_kind, _settings),
    do: {:error, {:credential_pool_empty, provider_kind}}

  def select_usable_account(accounts, provider_kind, settings) do
    usable = Enum.reject(accounts, &(account_unavailable_reason(&1, settings) != nil))

    case usable do
      [] ->
        skipped =
          Enum.map(accounts, fn account ->
            %{
              account_id: account.id,
              reason: account_unavailable_reason(account, settings) || "unavailable"
            }
          end)

        {:error, {:credential_pool_exhausted, provider_kind, skipped}}

      accounts ->
        account =
          case settings.rotation_strategy do
            "least_usage" -> choose_least_usage(accounts)
            _strategy -> choose_round_robin(provider_kind, accounts, settings)
          end

        {:ok, account}
    end
  end

  @spec account_matches_host?(map(), String.t() | nil) :: boolean()
  def account_matches_host?(%{worker_host: nil}, nil), do: true
  def account_matches_host?(%{worker_host: nil}, _worker_host), do: false
  def account_matches_host?(%{worker_host: host}, host), do: true
  def account_matches_host?(_account, _worker_host), do: false

  @spec worker_host(keyword()) :: String.t() | nil
  def worker_host(opts) when is_list(opts) do
    Keyword.get(opts, :worker_host) ||
      case Keyword.get(opts, :agent_runtime_target) do
        %{worker_host: worker_host} -> worker_host
        _target -> nil
      end
  end

  def worker_host(_opts), do: nil

  defp account_unavailable_reason(account, settings) do
    cond do
      account.enabled == false ->
        "disabled"

      account.state == "disabled" ->
        "disabled"

      paused?(account) ->
        paused_reason(account)

      cooldown_active?(account.exhausted_until) ->
        "cooling down until #{account.exhausted_until}"

      State.active_lease_count(account) >= settings.max_concurrent_leases_per_account ->
        "account concurrency limit reached"

      budget_exhausted?(account, settings) ->
        "daily token budget exhausted"

      true ->
        nil
    end
  end

  defp choose_least_usage(accounts) do
    accounts
    |> Enum.sort_by(&least_usage_sort_key/1)
    |> List.first()
  end

  defp least_usage_sort_key(account) do
    periods = Map.get(account, :rate_limit_periods) || %{}
    session_pct = RateLimits.bucket_usage_pct(Map.get(periods, "session"))
    weekly_pct = RateLimits.bucket_usage_pct(Map.get(periods, "weekly"))
    primary = max(session_pct, weekly_pct)

    {primary, RateLimits.bucket_total_tokens(Map.get(periods, "weekly")), RateLimits.bucket_total_tokens(Map.get(periods, "session")), account.id}
  end

  defp choose_round_robin(provider_kind, accounts, settings) do
    sorted_accounts = Enum.sort_by(accounts, & &1.id)
    rotation_path = Paths.rotation_path(provider_kind, settings)
    {:ok, rotation} = Files.read_json(rotation_path, %{})
    last_id = Map.get(rotation, "last_account_id")

    index =
      case Enum.find_index(sorted_accounts, &(&1.id == last_id)) do
        nil -> 0
        idx -> rem(idx + 1, length(sorted_accounts))
      end

    account = Enum.at(sorted_accounts, index)

    rotation =
      rotation
      |> Map.put("last_account_id", account.id)
      |> Map.put("updated_at", Normalization.now_iso())

    :ok = Files.write_json(rotation_path, rotation, Files.secret_mode())
    account
  end

  defp paused?(%{state: "paused", paused_until: nil}), do: true

  defp paused?(%{paused_until: paused_until}) when is_binary(paused_until),
    do: Normalization.future_iso?(paused_until)

  defp paused?(_account), do: false

  defp paused_reason(account),
    do:
      account.paused_reason ||
        if(account.paused_until, do: "paused until #{account.paused_until}", else: "paused")

  defp cooldown_active?(nil), do: false

  defp cooldown_active?(until_iso) when is_binary(until_iso),
    do: Normalization.future_iso?(until_iso)

  defp budget_exhausted?(account, settings) do
    budget = account.daily_token_budget || settings.daily_token_budget

    usage_total =
      token_total_for_period(account.token_totals, "daily", Date.utc_today() |> Date.to_iso8601())

    is_integer(budget) and budget > 0 and usage_total >= budget
  end

  defp token_total_for_period(token_totals, period_key, current_period)
       when is_map(token_totals) do
    period = Map.get(token_totals, period_key, %{})

    if Map.get(period, "period") == current_period,
      do: Normalization.integer_value(Map.get(period, "total_tokens")),
      else: 0
  end

  defp token_total_for_period(_token_totals, _period_key, _current_period), do: 0
end
