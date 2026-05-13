defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.SessionCreate do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Client.{Connection, Filters, Health, Session, SessionRequest, Transport}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{EventStreamSupervisor, SessionHandle}
  alias SymphonyWorkerDaemon.Protocol

  @public_client Module.concat(["SymphonyElixir", "Agent", "Runtime", "WorkerDaemon", "Client"])

  @spec create_session(CommandSpec.t(), Target.t(), keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def create_session(%CommandSpec{} = command_spec, %Target{} = target, opts \\ []) do
    with {:ok, endpoint} <- Connection.endpoint(target, opts),
         token <- Connection.token(opts),
         opts <- ensure_request_id(opts),
         {:ok, _health} <- Health.maybe_preflight(command_spec, target, endpoint, token, opts),
         request <- SessionRequest.create(command_spec, target, opts),
         {:ok, session_attrs} <- create_or_reconcile_session(request, target, endpoint, token, opts) do
      handle =
        SessionHandle.new(
          Map.merge(session_attrs, %{
            endpoint: endpoint,
            token: token,
            client: @public_client,
            metadata: handle_metadata(target, session_attrs)
          })
        )

      case maybe_start_event_stream(handle, opts) do
        :ok ->
          {:ok, handle}

        {:error, reason} ->
          _ = Session.stop_session(handle, opts)
          _ = Session.cleanup_session(handle, opts)
          {:error, {:worker_daemon_event_stream_start_failed, reason}}
      end
    end
  end

  defp ensure_request_id(opts) when is_list(opts) do
    case opts |> Keyword.get(:request_id) |> normalize_optional_string() do
      request_id when is_binary(request_id) -> Keyword.put(opts, :request_id, request_id)
      nil -> Keyword.put(opts, :request_id, Ecto.UUID.generate())
    end
  end

  defp create_or_reconcile_session(request, %Target{} = target, endpoint, token, opts) do
    case Transport.request(:post, endpoint, Protocol.sessions_path(), token, request, opts) do
      {:ok, payload} ->
        Protocol.normalize_create_response(payload)

      {:error, reason} ->
        maybe_reconcile_create_failure(reason, request, target, endpoint, token, opts)
    end
  end

  defp maybe_reconcile_create_failure(reason, request, target, endpoint, token, opts) do
    if reconcile_create_failure?(reason, opts) do
      case reconcile_created_session(request, target, endpoint, token, opts) do
        {:ok, session_attrs} -> {:ok, session_attrs}
        {:error, reconcile_reason} -> {:error, {:worker_daemon_create_uncertain, reason, reconcile_reason}}
      end
    else
      {:error, reason}
    end
  end

  defp reconcile_create_failure?(reason, opts) do
    Keyword.get(opts, :worker_daemon_reconcile_on_create_failure?, true) and uncertain_create_failure?(reason)
  end

  defp uncertain_create_failure?({:worker_daemon_request_failed, :post, _url, _reason}), do: true
  defp uncertain_create_failure?({:worker_daemon_error, :post, status, _code, _payload}) when is_integer(status), do: status >= 500
  defp uncertain_create_failure?(_reason), do: false

  defp reconcile_created_session(request, %Target{} = target, endpoint, token, opts) do
    attempts = positive_integer(opts, :worker_daemon_reconcile_attempts) || 3
    delay_ms = non_negative_integer(opts, :worker_daemon_reconcile_delay_ms, 50)
    session_id = expected_session_id(request)

    do_reconcile_created_session(attempts, delay_ms, session_id, request, target, endpoint, token, opts)
  end

  defp do_reconcile_created_session(0, _delay_ms, _session_id, _request, _target, _endpoint, _token, _opts) do
    {:error, :worker_daemon_reconcile_not_found}
  end

  defp do_reconcile_created_session(attempts, delay_ms, session_id, request, target, endpoint, token, opts) do
    case reconcile_by_session_status(session_id, endpoint, token, opts) do
      {:ok, session_attrs} ->
        {:ok, mark_reconciled(session_attrs, "session_status")}

      {:error, _status_reason} ->
        case reconcile_by_session_list(session_id, request, target, endpoint, token, opts) do
          {:ok, session_attrs} ->
            {:ok, mark_reconciled(session_attrs, "session_list")}

          {:error, _list_reason} ->
            if attempts > 1 do
              Process.sleep(delay_ms)
              do_reconcile_created_session(attempts - 1, delay_ms, session_id, request, target, endpoint, token, opts)
            else
              {:error, :worker_daemon_reconcile_not_found}
            end
        end
    end
  end

  defp reconcile_by_session_status(nil, _endpoint, _token, _opts), do: {:error, :worker_daemon_reconcile_session_id_missing}

  defp reconcile_by_session_status(session_id, endpoint, token, opts) when is_binary(session_id) do
    with {:ok, payload} <- Transport.request(:get, endpoint, Protocol.session_path(session_id), token, nil, opts) do
      session_attrs_from_status(payload, session_id)
    end
  end

  defp reconcile_by_session_list(nil, _request, _target, _endpoint, _token, _opts), do: {:error, :worker_daemon_reconcile_session_id_missing}

  defp reconcile_by_session_list(session_id, request, %Target{} = target, endpoint, token, opts) when is_binary(session_id) do
    filters =
      target
      |> Filters.session_filters(opts)
      |> Filters.put_optional_filter("run_id", request["run_id"])

    with {:ok, payload} <- Transport.request(:get, endpoint, Protocol.sessions_path(filters), token, nil, opts),
         {:ok, summaries} <- Protocol.normalize_session_list_response(payload),
         summary when is_map(summary) <- Enum.find(summaries, &(Map.get(&1, :session_id) == session_id)) do
      session_attrs_from_summary(summary)
    else
      nil -> {:error, :worker_daemon_reconcile_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp session_attrs_from_status(payload, expected_session_id) when is_map(payload) do
    status = normalize_response_string(payload, "status")
    session_id = normalize_response_string(payload, "session_id") || expected_session_id

    if is_binary(status) and is_binary(session_id) do
      {:ok,
       %{
         session_id: session_id,
         lease_id: normalize_response_string(payload, "lease_id"),
         worker_id: normalize_response_string(payload, "worker_id"),
         daemon_instance_id: normalize_response_string(payload, "daemon_instance_id"),
         status: status,
         metadata: %{
           worker_daemon_status: status,
           worker_daemon_reconciled: true
         }
       }
       |> compact_map()}
    else
      {:error, {:worker_daemon_reconcile_invalid_status_response, payload_summary(payload)}}
    end
  end

  defp session_attrs_from_status(payload, _expected_session_id), do: {:error, {:worker_daemon_reconcile_invalid_status_response, payload_summary(payload)}}

  defp session_attrs_from_summary(summary) when is_map(summary) do
    {:ok,
     %{
       session_id: Map.get(summary, :session_id),
       lease_id: Map.get(summary, :lease_id),
       status: Map.get(summary, :status),
       metadata: %{
         worker_daemon_status: Map.get(summary, :status),
         worker_daemon_reconciled: true
       }
     }
     |> compact_map()}
  end

  defp mark_reconciled(session_attrs, source) when is_map(session_attrs) and is_binary(source) do
    metadata =
      session_attrs
      |> Map.get(:metadata, %{})
      |> Map.put(:worker_daemon_reconciled, true)
      |> Map.put(:worker_daemon_reconcile_source, source)

    Map.put(session_attrs, :metadata, metadata)
  end

  defp expected_session_id(%{"session_id" => session_id}) when is_binary(session_id) and session_id != "", do: session_id
  defp expected_session_id(%{"request_id" => request_id}) when is_binary(request_id) and request_id != "", do: "session-" <> request_id
  defp expected_session_id(_request), do: nil

  defp maybe_start_event_stream(%SessionHandle{} = handle, opts) do
    if Keyword.get(opts, :worker_daemon_stream_events?, false) do
      owner = Keyword.get(opts, :worker_daemon_stream_owner, self())
      stream_opts = Keyword.drop(opts, [:worker_daemon_stream_owner])

      case EventStreamSupervisor.start_stream(handle, owner, stream_opts) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        :ignore -> {:error, :worker_daemon_event_stream_ignored}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp handle_metadata(%Target{} = target, session_attrs) do
    %{
      worker_pool: target.worker_pool,
      worker_host: target.worker_host,
      worker_placement: Atom.to_string(target.placement),
      run_id: Connection.metadata_value(target.metadata, :run_id),
      agent_provider_kind: Connection.metadata_value(target.metadata, :agent_provider_kind),
      worker_daemon_status: Map.get(session_attrs, :status)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> Map.merge(Map.get(session_attrs, :metadata, %{}))
  end

  defp normalize_response_string(payload, key) when is_map(payload) and is_binary(key) do
    payload
    |> response_value(key)
    |> normalize_optional_string()
  end

  defp response_value(map, "session_id"), do: known_key_value(map, "session_id", :session_id)
  defp response_value(map, "lease_id"), do: known_key_value(map, "lease_id", :lease_id)
  defp response_value(map, "worker_id"), do: known_key_value(map, "worker_id", :worker_id)
  defp response_value(map, "daemon_instance_id"), do: known_key_value(map, "daemon_instance_id", :daemon_instance_id)
  defp response_value(map, "status"), do: known_key_value(map, "status", :status)
  defp response_value(map, key), do: Map.get(map, key)

  defp known_key_value(map, string_key, atom_key) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp payload_summary(payload) when is_map(payload) do
    %{shape: "map", keys: payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}
  end

  defp payload_summary(payload), do: %{shape: inspect(payload)}

  defp positive_integer(opts, key) when is_list(opts) do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value > 0 -> value
      _value -> nil
    end
  end

  defp non_negative_integer(opts, key, default) when is_list(opts) and is_integer(default) and default >= 0 do
    case Keyword.get(opts, key) do
      value when is_integer(value) and value >= 0 -> value
      _value -> default
    end
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
end
