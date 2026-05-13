defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.EndpointState do
  @moduledoc false

  use GenServer

  @default_health_cache_ttl_ms 1_000
  @default_circuit_ttl_ms 2_000

  @type circuit_status :: :closed | {:open, map()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec reset() :: :ok
  def reset, do: call_if_running(:reset, :ok)

  @spec cached_health(String.t(), keyword()) :: {:ok, map()} | :miss
  def cached_health(endpoint, opts \\ []) when is_binary(endpoint) and is_list(opts) do
    if enabled?(opts) and health_cache_ttl_ms(opts) > 0 do
      call_if_running({:cached_health, endpoint, now_ms()}, :miss)
    else
      :miss
    end
  end

  @spec record_success(String.t(), map(), keyword()) :: :ok
  def record_success(endpoint, health, opts \\ []) when is_binary(endpoint) and is_map(health) and is_list(opts) do
    if enabled?(opts) do
      ttl_ms = health_cache_ttl_ms(opts)
      call_if_running({:record_success, endpoint, health, ttl_ms, now_ms()}, :ok)
    else
      :ok
    end
  end

  @spec record_failure(String.t(), term(), keyword()) :: :ok
  def record_failure(endpoint, reason, opts \\ []) when is_binary(endpoint) and is_list(opts) do
    if enabled?(opts) do
      ttl_ms = circuit_ttl_ms(opts)
      call_if_running({:record_failure, endpoint, safe_reason(reason), ttl_ms, now_ms()}, :ok)
    else
      :ok
    end
  end

  @spec circuit_status(String.t(), keyword()) :: circuit_status()
  def circuit_status(endpoint, opts \\ []) when is_binary(endpoint) and is_list(opts) do
    if enabled?(opts) and circuit_ttl_ms(opts) > 0 do
      call_if_running({:circuit_status, endpoint, now_ms()}, :closed)
    else
      :closed
    end
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{entries: %{}}}

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{entries: %{}}}

  def handle_call({:cached_health, endpoint, now_ms}, _from, state) do
    case Map.get(state.entries, endpoint) do
      %{health: health, health_expires_at_ms: expires_at} = entry when is_map(health) and is_integer(expires_at) ->
        if expires_at > now_ms do
          {:reply, {:ok, health}, state}
        else
          {:reply, :miss, put_entry(state, endpoint, Map.drop(entry, [:health, :health_expires_at_ms]))}
        end

      _entry ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:record_success, endpoint, health, ttl_ms, now_ms}, _from, state) do
    entry =
      state.entries
      |> Map.get(endpoint, %{})
      |> Map.drop([:circuit_expires_at_ms, :circuit_reason])
      |> maybe_put_health(health, ttl_ms, now_ms)

    {:reply, :ok, put_entry(state, endpoint, entry)}
  end

  def handle_call({:record_failure, endpoint, reason, ttl_ms, now_ms}, _from, state) do
    entry =
      state.entries
      |> Map.get(endpoint, %{})
      |> maybe_put_circuit(reason, ttl_ms, now_ms)

    {:reply, :ok, put_entry(state, endpoint, entry)}
  end

  def handle_call({:circuit_status, endpoint, now_ms}, _from, state) do
    case Map.get(state.entries, endpoint) do
      %{circuit_expires_at_ms: expires_at, circuit_reason: reason} = entry when is_integer(expires_at) ->
        if expires_at > now_ms do
          {:reply, {:open, %{reason: reason, retry_after_ms: expires_at - now_ms}}, state}
        else
          {:reply, :closed, put_entry(state, endpoint, Map.drop(entry, [:circuit_expires_at_ms, :circuit_reason]))}
        end

      _entry ->
        {:reply, :closed, state}
    end
  end

  defp maybe_put_health(entry, _health, ttl_ms, _now_ms) when ttl_ms <= 0, do: entry

  defp maybe_put_health(entry, health, ttl_ms, now_ms) do
    entry
    |> Map.put(:health, health)
    |> Map.put(:health_expires_at_ms, now_ms + ttl_ms)
  end

  defp maybe_put_circuit(entry, _reason, ttl_ms, _now_ms) when ttl_ms <= 0, do: entry

  defp maybe_put_circuit(entry, reason, ttl_ms, now_ms) do
    entry
    |> Map.put(:circuit_reason, reason)
    |> Map.put(:circuit_expires_at_ms, now_ms + ttl_ms)
  end

  defp put_entry(state, endpoint, entry) when map_size(entry) == 0 do
    %{state | entries: Map.delete(state.entries, endpoint)}
  end

  defp put_entry(state, endpoint, entry) do
    %{state | entries: Map.put(state.entries, endpoint, entry)}
  end

  defp call_if_running(request, default_value) do
    case GenServer.whereis(__MODULE__) do
      nil -> default_value
      _pid -> GenServer.call(__MODULE__, request)
    end
  catch
    :exit, _reason -> default_value
  end

  defp enabled?(opts), do: Keyword.get(opts, :worker_daemon_endpoint_state?, true)

  defp health_cache_ttl_ms(opts), do: non_negative_integer(opts, :worker_daemon_health_cache_ttl_ms, @default_health_cache_ttl_ms)
  defp circuit_ttl_ms(opts), do: non_negative_integer(opts, :worker_daemon_circuit_ttl_ms, @default_circuit_ttl_ms)

  defp non_negative_integer(opts, key, default) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value >= 0 -> value
      _value -> default
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp safe_reason(reason) when is_atom(reason), do: %{code: Atom.to_string(reason)}

  defp safe_reason({:worker_daemon_request_failed, method, _url, reason}) do
    %{
      code: "worker_daemon_request_failed",
      method: normalize_optional_string(method),
      reason: safe_reason(reason)
    }
    |> compact_map()
  end

  defp safe_reason({:worker_daemon_error, operation, status, code, _payload}) do
    %{
      code: normalize_optional_string(code),
      operation: normalize_optional_string(operation),
      status: status
    }
    |> compact_map()
  end

  defp safe_reason({:worker_daemon_not_ready, status}) do
    %{code: "worker_daemon_not_ready", status: normalize_optional_string(status)}
    |> compact_map()
  end

  defp safe_reason({:worker_daemon_missing_features, features}) when is_list(features) do
    %{code: "worker_daemon_missing_features", features: Enum.map(features, &to_string/1)}
  end

  defp safe_reason({:worker_daemon_worker_mismatch, expected, actual}) do
    %{
      code: "worker_daemon_worker_mismatch",
      expected: normalize_optional_string(expected),
      actual: normalize_optional_string(actual)
    }
    |> compact_map()
  end

  defp safe_reason(reason), do: %{code: "worker_daemon_endpoint_unavailable", reason: inspect(reason, limit: 20, printable_limit: 1_000)}

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end
end
