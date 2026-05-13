defmodule SymphonyElixir.Agent.Runtime.Executor.WorkerDaemon do
  @moduledoc false

  @behaviour SymphonyElixir.Agent.Runtime.Executor

  alias SymphonyElixir.Agent.Runtime.{CommandSpec, Target}
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.{Client, EndpointState, PoolResolver, SessionHandle}

  @impl true
  @spec start(CommandSpec.t(), Target.t(), keyword()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start(command_spec, target, opts \\ [])

  def start(%CommandSpec{} = command_spec, %Target{placement: :worker_daemon} = target, opts) do
    client = Keyword.get(opts, :worker_daemon_client, Client)

    opts =
      opts
      |> stream_opts()
      |> ensure_request_id()

    if Keyword.get(opts, :worker_daemon_create_failover?, true) and not explicit_endpoint?(opts) do
      start_with_failover(client, command_spec, target, opts)
    else
      client.create_session(command_spec, target, opts)
    end
  end

  def start(%CommandSpec{} = command_spec, %Target{} = target, _opts) do
    {:error,
     {:worker_daemon_invalid_target,
      %{
        worker_placement: Atom.to_string(target.placement),
        command: CommandSpec.command_summary(command_spec)
      }}}
  end

  @impl true
  @spec stop(term(), keyword()) :: :ok | {:error, term()}
  def stop(handle, opts \\ [])

  def stop(%SessionHandle{} = handle, opts) do
    stop_result = SessionHandle.stop(handle, opts)
    cleanup_result = SessionHandle.cleanup(handle, opts)

    case {stop_result, cleanup_result} do
      {:ok, :ok} -> :ok
      {{:error, reason}, :ok} -> {:error, reason}
      {:ok, {:error, reason}} -> {:error, reason}
      {{:error, stop_reason}, {:error, cleanup_reason}} -> {:error, {:worker_daemon_stop_cleanup_failed, stop_reason, cleanup_reason}}
    end
  end

  def stop(_handle, _opts), do: :ok

  @impl true
  @spec alive?(term()) :: boolean()
  def alive?(%SessionHandle{} = handle), do: SessionHandle.alive?(handle)
  def alive?(_handle), do: false

  defp stream_opts(opts) when is_list(opts) do
    Keyword.put_new(opts, :worker_daemon_stream_events?, true)
  end

  defp ensure_request_id(opts) when is_list(opts) do
    case opts |> Keyword.get(:request_id) |> normalize_optional_string() do
      request_id when is_binary(request_id) -> Keyword.put(opts, :request_id, request_id)
      nil -> Keyword.put(opts, :request_id, Ecto.UUID.generate())
    end
  end

  defp start_with_failover(client, command_spec, target, opts) do
    targets = failover_targets(target, opts)

    case targets do
      [_target, _next | _rest] -> do_start_with_failover(targets, client, command_spec, opts, [])
      _targets -> client.create_session(command_spec, target, opts)
    end
  end

  defp do_start_with_failover([], _client, _command_spec, _opts, failures) do
    {:error, {:worker_daemon_create_pool_unavailable, Enum.reverse(failures)}}
  end

  defp do_start_with_failover([target | rest], client, command_spec, opts, failures) do
    case client.create_session(command_spec, target, opts) do
      {:ok, %SessionHandle{metadata: metadata} = handle} ->
        {:ok, %{handle | metadata: Map.put(metadata || %{}, :worker_daemon_create_failover_failures, Enum.reverse(failures))}}

      {:error, reason} ->
        if rest != [] and retryable_create_failure?(reason) do
          record_retryable_create_failure(target, reason, opts)
          do_start_with_failover(rest, client, command_spec, opts, [failure(target, reason) | failures])
        else
          {:error, reason}
        end
    end
  end

  defp failover_targets(%Target{} = target, opts) do
    current_candidate = current_candidate(target)

    target
    |> PoolResolver.candidates(opts)
    |> then(&[current_candidate | &1])
    |> unique_candidates()
    |> Enum.map(&target_for_candidate(target, &1, opts))
  end

  defp current_candidate(%Target{} = target) do
    %{
      endpoint: metadata_value(target.metadata, :worker_daemon_endpoint),
      worker_id: metadata_value(target.metadata, :worker_daemon_worker_id),
      endpoint_id: metadata_value(target.metadata, :worker_daemon_endpoint_id),
      source: metadata_value(target.metadata, :worker_daemon_endpoint_source)
    }
    |> compact_map()
  end

  defp target_for_candidate(%Target{} = target, candidate, opts) when is_map(candidate) do
    metadata =
      target.metadata
      |> Map.put(:worker_daemon_endpoint, Map.fetch!(candidate, :endpoint))
      |> maybe_put(:worker_daemon_endpoint_id, Map.get(candidate, :endpoint_id))
      |> maybe_put(:worker_daemon_endpoint_source, Map.get(candidate, :source))
      |> put_candidate_worker_id(candidate, opts)

    %Target{target | metadata: metadata}
  end

  defp put_candidate_worker_id(metadata, candidate, opts) do
    case normalize_optional_string(Keyword.get(opts, :worker_daemon_worker_id)) || Map.get(candidate, :worker_id) do
      nil -> Map.delete(metadata, :worker_daemon_worker_id)
      worker_id -> Map.put(metadata, :worker_daemon_worker_id, worker_id)
    end
  end

  defp retryable_create_failure?({:worker_daemon_error, :post, status, code, _payload})
       when status in [409, 429] and code in ["worker_full", "worker_draining", "worker_unavailable", "queue_full", "budget_exceeded"],
       do: true

  defp retryable_create_failure?(_reason), do: false

  defp record_retryable_create_failure(%Target{} = target, reason, opts) do
    case metadata_value(target.metadata, :worker_daemon_endpoint) do
      endpoint when is_binary(endpoint) -> EndpointState.record_failure(endpoint, reason, opts)
      _endpoint -> :ok
    end
  end

  defp explicit_endpoint?(opts) when is_list(opts) do
    not is_nil(normalize_optional_string(Keyword.get(opts, :worker_daemon_endpoint)))
  end

  defp failure(%Target{} = target, reason) do
    %{
      endpoint: metadata_value(target.metadata, :worker_daemon_endpoint),
      worker_id: metadata_value(target.metadata, :worker_daemon_worker_id),
      endpoint_id: metadata_value(target.metadata, :worker_daemon_endpoint_id),
      source: metadata_value(target.metadata, :worker_daemon_endpoint_source),
      reason: safe_reason(reason)
    }
    |> compact_map()
  end

  defp safe_reason({:worker_daemon_error, _operation, status, code, _payload}) do
    %{code: code, status: status}
  end

  defp safe_reason(reason), do: inspect(reason, limit: 20, printable_limit: 1_000)

  defp unique_candidates(candidates) when is_list(candidates) do
    candidates
    |> Enum.filter(&(is_map(&1) and is_binary(Map.get(&1, :endpoint))))
    |> Enum.reduce({MapSet.new(), []}, fn candidate, {seen, acc} ->
      if MapSet.member?(seen, candidate.endpoint) do
        {seen, acc}
      else
        {MapSet.put(seen, candidate.endpoint), [candidate | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp metadata_value(metadata, key) when is_map(metadata), do: Map.get(metadata, key) || Map.get(metadata, Atom.to_string(key))
  defp metadata_value(_metadata, _key), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil
end
