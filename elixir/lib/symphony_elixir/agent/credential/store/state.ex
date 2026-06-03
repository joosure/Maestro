defmodule SymphonyElixir.Agent.Credential.Store.State do
  @moduledoc false

  alias SymphonyElixir.Agent.Credential.Store.Normalization

  @states ["healthy", "unknown", "limited", "exhausted", "paused", "disabled"]

  @spec default() :: map()
  def default do
    %{
      "state" => "unknown",
      "latest_quota" => nil,
      "exhausted_until" => nil,
      "failure_reason" => nil,
      "last_success_at" => nil,
      "token_totals" => default_token_totals(),
      "rate_limit_periods" => %{},
      "active_leases" => %{},
      "updated_at" => Normalization.now_iso()
    }
  end

  @spec default_token_totals() :: map()
  def default_token_totals do
    %{
      "total" => %{"input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0},
      "daily" => %{
        "period" => Date.utc_today() |> Date.to_iso8601(),
        "input_tokens" => 0,
        "output_tokens" => 0,
        "total_tokens" => 0
      }
    }
  end

  @spec normalize_state(term()) :: String.t()
  def normalize_state(state) when state in @states, do: state
  def normalize_state(_state), do: "unknown"

  @spec effective_state(String.t(), map()) :: String.t()
  def effective_state(_state, %{"enabled" => false}), do: "disabled"

  def effective_state(_state, %{"paused_until" => paused_until}) when is_binary(paused_until) do
    if Normalization.future_iso?(paused_until), do: "paused", else: "unknown"
  end

  def effective_state(state, _metadata), do: state

  @spec mark_success(map()) :: map()
  def mark_success(state) do
    state
    |> Map.put("last_success_at", Normalization.now_iso())
    |> Map.update("state", "healthy", fn
      state when state in ["unknown", "limited"] -> "healthy"
      state -> state
    end)
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec mark_exhausted(map(), term(), map()) :: map()
  def mark_exhausted(state, reason, settings) do
    until_iso =
      DateTime.utc_now()
      |> DateTime.add(settings.exhausted_cooldown_ms, :millisecond)
      |> DateTime.to_iso8601()

    Map.merge(state, %{
      "state" => "exhausted",
      "exhausted_until" => until_iso,
      "failure_reason" => reason |> inspect(limit: 20, printable_limit: 500) |> String.slice(0, 500),
      "updated_at" => Normalization.now_iso()
    })
  end

  @spec pause(map(), String.t()) :: map()
  def pause(state, reason) do
    Map.merge(state, %{
      "state" => "paused",
      "failure_reason" => reason,
      "updated_at" => Normalization.now_iso()
    })
  end

  @spec resume(map()) :: map()
  def resume(state) do
    Map.merge(state, %{
      "state" => "unknown",
      "failure_reason" => nil,
      "exhausted_until" => nil,
      "updated_at" => Normalization.now_iso()
    })
  end

  @spec set_enabled(map(), boolean()) :: map()
  def set_enabled(state, enabled) when is_boolean(enabled) do
    state
    |> Map.put("state", if(enabled, do: "unknown", else: "disabled"))
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec release_lease(map(), String.t()) :: map()
  def release_lease(state, lease_id) when is_binary(lease_id) do
    active_leases =
      state
      |> Map.get("active_leases", %{})
      |> Map.delete(lease_id)

    state
    |> Map.put("active_leases", active_leases)
    |> Map.put("updated_at", Normalization.now_iso())
  end

  @spec active_lease_count(map()) :: non_neg_integer()
  def active_lease_count(%{active_leases: leases}) when is_map(leases), do: map_size(leases)
  def active_lease_count(_account), do: 0

  @spec prune_expired_leases(map(), DateTime.t()) :: map()
  def prune_expired_leases(active_leases, %DateTime{} = now) when is_map(active_leases) do
    active_leases
    |> prune_inactive_leases(now)
    |> elem(0)
  end

  def prune_expired_leases(_active_leases, _now), do: %{}

  @spec prune_inactive_leases(map(), DateTime.t()) :: {map(), [map()]}
  @spec prune_inactive_leases(map(), DateTime.t(), keyword()) :: {map(), [map()]}
  def prune_inactive_leases(active_leases, now, opts \\ [])

  def prune_inactive_leases(active_leases, %DateTime{} = now, opts) when is_map(active_leases) and is_list(opts) do
    Enum.reduce(active_leases, %{}, fn {lease_id, lease}, acc ->
      case inactive_lease_reason(lease, now, opts) do
        nil ->
          Map.update(acc, :kept, %{lease_id => lease}, &Map.put(&1, lease_id, lease))

        reason ->
          pruned = %{
            lease_id: lease_id,
            reason: reason,
            run_id: Map.get(lease, "run_id"),
            worker_host: Map.get(lease, "worker_host"),
            acquired_at: Map.get(lease, "acquired_at"),
            expires_at: Map.get(lease, "expires_at"),
            owner_node: Map.get(lease, "owner_node"),
            owner_pid: Map.get(lease, "owner_pid")
          }

          Map.update(acc, :pruned, [pruned], &[pruned | &1])
      end
    end)
    |> case do
      %{kept: kept, pruned: pruned} -> {kept, Enum.reverse(pruned)}
      %{kept: kept} -> {kept, []}
      %{pruned: pruned} -> {%{}, Enum.reverse(pruned)}
      %{} -> {%{}, []}
    end
  end

  def prune_inactive_leases(_active_leases, _now, _opts), do: {%{}, []}

  defp inactive_lease_reason(lease, now, opts) when is_map(lease) and is_struct(now, DateTime) and is_list(opts) do
    cond do
      expired?(lease, now) ->
        "expired"

      local_owner_stale?(lease) ->
        "stale_owner"

      ownerless_stale?(lease, now, opts) ->
        "stale_ownerless"

      true ->
        nil
    end
  end

  defp inactive_lease_reason(_lease, _now, _opts), do: nil

  defp expired?(lease, now) do
    case lease |> Map.get("expires_at") |> Normalization.normalize_datetime() do
      %DateTime{} = expires_at -> DateTime.compare(expires_at, now) != :gt
      _datetime -> false
    end
  end

  defp local_owner_stale?(%{"owner_node" => owner_node, "owner_pid" => owner_pid})
       when is_binary(owner_node) and is_binary(owner_pid) do
    owner_node == Atom.to_string(node()) and not local_pid_alive?(owner_pid)
  end

  defp local_owner_stale?(_lease), do: false

  defp ownerless_stale?(lease, now, opts) when is_map(lease) do
    stale_after_ms = Keyword.get(opts, :ownerless_stale_recovery_after_ms)

    cond do
      not (is_integer(stale_after_ms) and stale_after_ms > 0) ->
        false

      Map.has_key?(lease, "owner_node") and Map.has_key?(lease, "owner_pid") ->
        false

      true ->
        lease
        |> Map.get("acquired_at")
        |> Normalization.normalize_datetime()
        |> case do
          %DateTime{} = acquired_at -> DateTime.diff(now, acquired_at, :millisecond) >= stale_after_ms
          _datetime -> false
        end
    end
  end

  defp local_pid_alive?(pid_string) when is_binary(pid_string) do
    pid_string
    |> String.to_charlist()
    |> :erlang.list_to_pid()
    |> Process.alive?()
  rescue
    _error -> false
  end
end
