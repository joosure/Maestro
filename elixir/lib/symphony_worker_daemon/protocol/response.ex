defmodule SymphonyWorkerDaemon.Protocol.Response do
  @moduledoc false

  alias SymphonyElixir.Observability.Redaction
  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields
  alias SymphonyWorkerDaemon.Session.Status

  @status_key ProtocolFields.status()
  @protocol_version_key ProtocolFields.protocol_version()
  @daemon_version_key ProtocolFields.daemon_version()
  @daemon_software_version_key ProtocolFields.daemon_software_version()
  @worker_id_key ProtocolFields.worker_id()
  @daemon_instance_id_key ProtocolFields.daemon_instance_id()
  @worker_profile_version_key ProtocolFields.worker_profile_version()
  @capacity_key ProtocolFields.capacity()
  @features_key ProtocolFields.features()
  @capabilities_key ProtocolFields.capabilities()
  @session_id_key ProtocolFields.session_id()
  @lease_id_key ProtocolFields.lease_id()
  @metadata_key ProtocolFields.metadata()
  @sessions_key ProtocolFields.sessions()
  @events_key ProtocolFields.events()
  @run_id_key ProtocolFields.run_id()
  @owner_key ProtocolFields.owner()
  @tenant_id_key ProtocolFields.tenant_id()
  @provider_kind_key ProtocolFields.provider_kind()
  @worker_pool_key ProtocolFields.worker_pool()
  @cwd_key ProtocolFields.cwd()
  @os_pid_key ProtocolFields.os_pid()
  @exit_status_key ProtocolFields.exit_status()
  @started_at_ms_key ProtocolFields.started_at_ms()
  @updated_at_ms_key ProtocolFields.updated_at_ms()
  @event_id_key ProtocolFields.event_id()
  @type_key ProtocolFields.type()
  @stream_key ProtocolFields.stream()
  @data_key ProtocolFields.data()
  @timestamp_ms_key ProtocolFields.timestamp_ms()
  @code_key ProtocolFields.code()
  @safe_error_keys ProtocolFields.safe_error_keys()
  @terminal_statuses MapSet.new(Status.terminal_statuses())

  @spec normalize_health_response(term()) :: {:ok, map()} | {:error, term()}
  def normalize_health_response(%{@status_key => status, @protocol_version_key => protocol_version} = payload)
      when is_binary(status) and is_binary(protocol_version) do
    {:ok,
     %{
       status: status,
       protocol_version: protocol_version,
       daemon_version: optional_string(Map.get(payload, @daemon_version_key) || Map.get(payload, @daemon_software_version_key)),
       worker_id: optional_string(Map.get(payload, @worker_id_key)),
       daemon_instance_id: optional_string(Map.get(payload, @daemon_instance_id_key)),
       worker_profile_version: optional_string(Map.get(payload, @worker_profile_version_key)),
       capacity: normalize_map(Map.get(payload, @capacity_key)),
       features: string_list(Map.get(payload, @features_key)),
       capabilities: normalize_capabilities(Map.get(payload, @capabilities_key))
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
  def normalize_create_response(%{@session_id_key => session_id} = payload) when is_binary(session_id) do
    {:ok,
     %{
       session_id: session_id,
       worker_id: optional_string(Map.get(payload, @worker_id_key)),
       daemon_instance_id: optional_string(Map.get(payload, @daemon_instance_id_key)),
       lease_id: optional_string(Map.get(payload, @lease_id_key)),
       status: optional_string(Map.get(payload, @status_key)),
       metadata: normalize_map(Map.get(payload, @metadata_key))
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
  def normalize_status(%{@status_key => status}) when is_binary(status), do: {:ok, status}
  def normalize_status(%{status: status}) when is_binary(status), do: {:ok, status}
  def normalize_status(payload), do: {:error, {:worker_daemon_invalid_status_response, payload_summary(payload)}}

  @spec normalize_session_list_response(term()) :: {:ok, [map()]} | {:error, term()}
  def normalize_session_list_response(%{@sessions_key => sessions}) when is_list(sessions) do
    {:ok, Enum.flat_map(sessions, &normalize_session_summary/1)}
  end

  def normalize_session_list_response(%{sessions: sessions}) when is_list(sessions) do
    normalize_session_list_response(%{@sessions_key => sessions})
  end

  def normalize_session_list_response(payload), do: {:error, {:worker_daemon_invalid_session_list_response, payload_summary(payload)}}

  @spec normalize_session_events_response(term()) :: {:ok, [map()]} | {:error, term()}
  def normalize_session_events_response(%{@events_key => events}) when is_list(events) do
    {:ok, Enum.flat_map(events, &normalize_session_event/1)}
  end

  def normalize_session_events_response(%{events: events}) when is_list(events) do
    normalize_session_events_response(%{@events_key => events})
  end

  def normalize_session_events_response(payload), do: {:error, {:worker_daemon_invalid_session_events_response, payload_summary(payload)}}

  @spec terminal_status?(String.t()) :: boolean()
  def terminal_status?(status) when is_binary(status), do: MapSet.member?(@terminal_statuses, status)

  @spec error_reason(atom(), pos_integer() | nil, term()) :: term()
  def error_reason(operation, status, %{@code_key => code} = payload) when is_binary(code) do
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

  defp normalize_session_summary(%{@session_id_key => session_id} = payload) when is_binary(session_id) do
    [
      session_id: session_id,
      status: optional_string(Map.get(payload, @status_key)),
      run_id: optional_string(Map.get(payload, @run_id_key)),
      owner: optional_string(Map.get(payload, @owner_key)),
      tenant_id: optional_string(Map.get(payload, @tenant_id_key)),
      provider_kind: optional_string(Map.get(payload, @provider_kind_key)),
      worker_pool: optional_string(Map.get(payload, @worker_pool_key)),
      lease_id: optional_string(Map.get(payload, @lease_id_key)),
      cwd: optional_string(Map.get(payload, @cwd_key)),
      os_pid: optional_integer(Map.get(payload, @os_pid_key)),
      exit_status: optional_integer(Map.get(payload, @exit_status_key)),
      started_at_ms: optional_integer(Map.get(payload, @started_at_ms_key)),
      updated_at_ms: optional_integer(Map.get(payload, @updated_at_ms_key))
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

  defp normalize_session_event(%{@event_id_key => event_id, @type_key => type} = payload)
       when is_integer(event_id) and is_binary(type) do
    [
      event_id: event_id,
      type: type,
      stream: optional_string(Map.get(payload, @stream_key)),
      data: optional_binary(Map.get(payload, @data_key)),
      timestamp_ms: optional_integer(Map.get(payload, @timestamp_ms_key))
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

      if string_key in @safe_error_keys do
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
