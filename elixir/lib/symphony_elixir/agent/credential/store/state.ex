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
    Enum.reduce(active_leases, %{}, fn {lease_id, lease}, acc ->
      case lease |> Map.get("expires_at") |> Normalization.normalize_datetime() do
        %DateTime{} = expires_at ->
          if DateTime.compare(expires_at, now) == :gt,
            do: Map.put(acc, lease_id, lease),
            else: acc

        _datetime ->
          Map.put(acc, lease_id, lease)
      end
    end)
  end

  def prune_expired_leases(_active_leases, _now), do: %{}
end
