defmodule SymphonyWorkerDaemon.Protocol.Response do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction

  @terminal_statuses MapSet.new(["exited", "failed", "lost", "cleaned", "stopped"])

  @spec normalize_health_response(term()) :: {:ok, map()} | {:error, term()}
  def normalize_health_response(%{"status" => status, "protocol_version" => protocol_version} = payload)
      when is_binary(status) and is_binary(protocol_version) do
    {:ok,
     %{
       status: status,
       protocol_version: protocol_version,
       daemon_version: optional_string(payload["daemon_version"] || payload["daemon_software_version"]),
       worker_id: optional_string(payload["worker_id"]),
       daemon_instance_id: optional_string(payload["daemon_instance_id"]),
       worker_profile_version: optional_string(payload["worker_profile_version"]),
       capacity: normalize_map(payload["capacity"]),
       features: string_list(payload["features"]),
       capabilities: normalize_capabilities(payload["capabilities"])
     }
     |> compact_map()}
  end

  def normalize_health_response(%{status: _status, protocol_version: _protocol_version} = payload) do
    payload
    |> atom_payload_to_string_payload()
    |> normalize_health_response()
  end

  def normalize_health_response(payload), do: {:error, {:worker_daemon_invalid_health_response, payload_summary(payload)}}

  @spec normalize_create_response(term()) :: {:ok, map()} | {:error, term()}
  def normalize_create_response(%{"session_id" => session_id} = payload) when is_binary(session_id) do
    {:ok,
     %{
       session_id: session_id,
       worker_id: optional_string(payload["worker_id"]),
       daemon_instance_id: optional_string(payload["daemon_instance_id"]),
       lease_id: optional_string(payload["lease_id"]),
       status: optional_string(payload["status"]),
       metadata: normalize_map(payload["metadata"])
     }
     |> compact_map()}
  end

  def normalize_create_response(%{session_id: session_id} = payload) when is_binary(session_id) do
    payload
    |> atom_payload_to_string_payload()
    |> normalize_create_response()
  end

  def normalize_create_response(payload), do: {:error, {:worker_daemon_invalid_create_response, payload_summary(payload)}}

  @spec normalize_status(term()) :: {:ok, String.t()} | {:error, term()}
  def normalize_status(%{"status" => status}) when is_binary(status), do: {:ok, status}
  def normalize_status(%{status: status}) when is_binary(status), do: {:ok, status}
  def normalize_status(payload), do: {:error, {:worker_daemon_invalid_status_response, payload_summary(payload)}}

  @spec normalize_session_list_response(term()) :: {:ok, [map()]} | {:error, term()}
  def normalize_session_list_response(%{"sessions" => sessions}) when is_list(sessions) do
    {:ok, Enum.flat_map(sessions, &normalize_session_summary/1)}
  end

  def normalize_session_list_response(%{sessions: sessions}) when is_list(sessions) do
    normalize_session_list_response(%{"sessions" => sessions})
  end

  def normalize_session_list_response(payload), do: {:error, {:worker_daemon_invalid_session_list_response, payload_summary(payload)}}

  @spec normalize_session_events_response(term()) :: {:ok, [map()]} | {:error, term()}
  def normalize_session_events_response(%{"events" => events}) when is_list(events) do
    {:ok, Enum.flat_map(events, &normalize_session_event/1)}
  end

  def normalize_session_events_response(%{events: events}) when is_list(events) do
    normalize_session_events_response(%{"events" => events})
  end

  def normalize_session_events_response(payload), do: {:error, {:worker_daemon_invalid_session_events_response, payload_summary(payload)}}

  @spec terminal_status?(String.t()) :: boolean()
  def terminal_status?(status) when is_binary(status), do: MapSet.member?(@terminal_statuses, status)

  @spec error_reason(atom(), pos_integer() | nil, term()) :: term()
  def error_reason(operation, status, %{"code" => code} = payload) when is_binary(code) do
    {:worker_daemon_error, operation, status, code, safe_error_payload(payload)}
  end

  def error_reason(operation, status, %{code: code} = payload) when is_binary(code) do
    {:worker_daemon_error, operation, status, code, safe_error_payload(payload)}
  end

  def error_reason(operation, status, payload) do
    {:worker_daemon_error, operation, status, "unknown", payload_summary(payload)}
  end

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil

  defp optional_binary(value) when is_binary(value), do: value
  defp optional_binary(_value), do: nil

  defp string_list(values) when is_list(values) do
    values
    |> Enum.map(&optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp string_list(_values), do: []

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    Enum.filter(capabilities, &is_map/1)
  end

  defp normalize_capabilities(_capabilities), do: []

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp atom_payload_to_string_payload(payload) when is_map(payload) do
    Map.new(payload, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_session_summary(%{"session_id" => session_id} = payload) when is_binary(session_id) do
    [
      session_id: session_id,
      status: optional_string(payload["status"]),
      run_id: optional_string(payload["run_id"]),
      owner: optional_string(payload["owner"]),
      tenant_id: optional_string(payload["tenant_id"]),
      provider_kind: optional_string(payload["provider_kind"]),
      worker_pool: optional_string(payload["worker_pool"]),
      lease_id: optional_string(payload["lease_id"]),
      cwd: optional_string(payload["cwd"]),
      os_pid: optional_integer(payload["os_pid"]),
      exit_status: optional_integer(payload["exit_status"]),
      started_at_ms: optional_integer(payload["started_at_ms"]),
      updated_at_ms: optional_integer(payload["updated_at_ms"])
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> List.wrap()
  end

  defp normalize_session_summary(%{session_id: _session_id} = payload) do
    payload
    |> atom_payload_to_string_payload()
    |> normalize_session_summary()
  end

  defp normalize_session_summary(_payload), do: []

  defp normalize_session_event(%{"event_id" => event_id, "type" => type} = payload)
       when is_integer(event_id) and is_binary(type) do
    [
      event_id: event_id,
      type: type,
      stream: optional_string(payload["stream"]),
      data: optional_binary(payload["data"]),
      timestamp_ms: optional_integer(payload["timestamp_ms"])
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> List.wrap()
  end

  defp normalize_session_event(%{event_id: _event_id, type: _type} = payload) do
    payload
    |> atom_payload_to_string_payload()
    |> normalize_session_event()
  end

  defp normalize_session_event(_payload), do: []

  defp optional_integer(value) when is_integer(value), do: value
  defp optional_integer(_value), do: nil

  defp safe_error_payload(payload) when is_map(payload) do
    payload
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      string_key = to_string(key)

      if string_key in ["code", "message", "retryable", "retryable?", "details"] do
        Map.put(acc, string_key, value)
      else
        acc
      end
    end)
    |> Redaction.redact()
  end

  defp payload_summary(payload) when is_map(payload), do: %{shape: "map", keys: Map.keys(payload) |> Enum.map(&to_string/1) |> Enum.sort()}
  defp payload_summary(payload), do: %{shape: inspect(payload)}
end
