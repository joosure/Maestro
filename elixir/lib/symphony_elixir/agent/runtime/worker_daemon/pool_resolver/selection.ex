defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.Selection do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Endpoint

  @spec target_for_candidate(Target.t(), map()) :: Target.t()
  def target_for_candidate(%Target{} = target, candidate) when is_map(candidate) do
    metadata =
      target.metadata
      |> Map.put(:worker_daemon_endpoint, Map.fetch!(candidate, :endpoint))
      |> maybe_put(:worker_daemon_worker_id, map_value(target.metadata, :worker_daemon_worker_id) || Map.get(candidate, :worker_id))

    %Target{target | metadata: metadata}
  end

  @spec success(map(), map(), String.t()) :: map()
  def success(candidate, health, health_source) when is_map(candidate) and is_map(health) and is_binary(health_source) do
    %{
      endpoint: candidate.endpoint,
      worker_id: Map.get(health, :worker_id) || Map.get(candidate, :worker_id),
      daemon_instance_id: Map.get(health, :daemon_instance_id),
      endpoint_id: Map.get(candidate, :endpoint_id),
      source: Map.get(candidate, :source),
      health_source: health_source,
      health: safe_health(health)
    }
    |> compact_map()
  end

  @spec failure(map(), term()) :: map()
  def failure(candidate, reason) when is_map(candidate) do
    %{
      endpoint: safe_endpoint(candidate.endpoint),
      worker_id: Map.get(candidate, :worker_id),
      endpoint_id: Map.get(candidate, :endpoint_id),
      source: Map.get(candidate, :source),
      reason: safe_reason(reason)
    }
    |> compact_map()
  end

  @spec safe_reason(term()) :: term()
  def safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  def safe_reason({:worker_daemon_request_failed, method, url, reason}) do
    %{
      code: "worker_daemon_request_failed",
      method: normalize_optional_string(method),
      url: safe_endpoint(url),
      reason: safe_reason(reason)
    }
    |> compact_map()
  end

  def safe_reason({:worker_daemon_not_ready, status}) do
    %{code: "worker_daemon_not_ready", status: normalize_optional_string(status)}
    |> compact_map()
  end

  def safe_reason({:worker_daemon_protocol_mismatch, expected, actual}) do
    %{
      code: "worker_daemon_protocol_mismatch",
      expected: normalize_optional_string(expected),
      actual: normalize_optional_string(actual)
    }
    |> compact_map()
  end

  def safe_reason({:worker_daemon_missing_features, features}) do
    %{code: "worker_daemon_missing_features", features: normalize_string_list(features)}
    |> compact_map()
  end

  def safe_reason({:worker_daemon_worker_mismatch, expected, actual}) do
    %{
      code: "worker_daemon_worker_mismatch",
      expected: normalize_optional_string(expected),
      actual: normalize_optional_string(actual)
    }
    |> compact_map()
  end

  def safe_reason({:worker_daemon_circuit_open, details}) when is_map(details) do
    %{code: "worker_daemon_circuit_open", details: details}
    |> compact_map()
  end

  def safe_reason(reason), do: inspect(reason, limit: 20, printable_limit: 1_000)

  defp safe_health(health) when is_map(health) do
    health
    |> Map.take([:status, :protocol_version, :daemon_version, :worker_id, :daemon_instance_id, :worker_profile_version, :capacity, :features, :capabilities])
    |> compact_map()
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []

  defp safe_endpoint(value), do: Endpoint.safe(value)

  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
