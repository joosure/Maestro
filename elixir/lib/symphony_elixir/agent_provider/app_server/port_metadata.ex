defmodule SymphonyElixir.AgentProvider.AppServer.PortMetadata do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Handle
  alias SymphonyElixir.Platform.Process, as: PlatformProcess

  @spec metadata(String.t(), term(), String.t() | nil, String.t() | nil) :: map()
  def metadata(agent_provider_kind, process_ref, worker_host \\ nil, run_id \\ nil)
      when is_binary(agent_provider_kind) do
    agent_provider_kind
    |> base_metadata(process_ref, run_id)
    |> maybe_put_worker_host(worker_host)
  end

  @spec message(String.t(), term(), map(), map() | nil) :: map()
  def message(agent_provider_kind, process_ref, payload, turn_context) when is_binary(agent_provider_kind) do
    agent_provider_kind
    |> metadata(process_ref)
    |> maybe_set_usage(payload)
    |> merge_turn_context(turn_context)
  end

  defp base_metadata(agent_provider_kind, port, run_id) when is_port(port) do
    %{agent_provider_kind: agent_provider_kind}
    |> maybe_put_run_id(run_id)
    |> maybe_put_agent_process_pid(port)
  end

  defp base_metadata(agent_provider_kind, handle, run_id) do
    %{agent_provider_kind: agent_provider_kind}
    |> maybe_put_run_id(run_id)
    |> Map.merge(Handle.safe_metadata(handle))
  end

  defp maybe_put_agent_process_pid(metadata, port) when is_port(port) do
    case PlatformProcess.port_os_pid(port) do
      os_pid when is_integer(os_pid) -> Map.put(metadata, :agent_process_pid, to_string(os_pid))
      _pid -> metadata
    end
  end

  defp maybe_put_run_id(metadata, run_id) when is_binary(run_id), do: Map.put(metadata, :run_id, run_id)
  defp maybe_put_run_id(metadata, _run_id), do: metadata

  defp maybe_put_worker_host(metadata, worker_host) when is_binary(worker_host), do: Map.put(metadata, :worker_host, worker_host)
  defp maybe_put_worker_host(metadata, _worker_host), do: metadata

  defp maybe_set_usage(metadata, payload) when is_map(payload) do
    usage = Map.get(payload, "usage") || Map.get(payload, :usage)

    if is_map(usage) do
      Map.put(metadata, :usage, usage)
    else
      metadata
    end
  end

  defp maybe_set_usage(metadata, _payload), do: metadata

  defp merge_turn_context(metadata, turn_context) when is_map(turn_context) do
    metadata
    |> maybe_put_context(:run_id, Map.get(turn_context, :run_id))
    |> maybe_put_context(:correlation_id, Map.get(turn_context, :run_id))
    |> maybe_put_context(:session_id, Map.get(turn_context, :session_id))
    |> maybe_put_context(:thread_id, Map.get(turn_context, :thread_id))
    |> maybe_put_context(:turn_id, Map.get(turn_context, :turn_id))
    |> maybe_put_context(:workspace_path, Map.get(turn_context, :workspace))
    |> maybe_put_context(:worker_host, Map.get(turn_context, :worker_host))
    |> maybe_put_context(:issue_id, turn_context |> Map.get(:issue) |> issue_value(:id))
    |> maybe_put_context(:issue_identifier, turn_context |> Map.get(:issue) |> issue_value(:identifier))
  end

  defp merge_turn_context(metadata, _turn_context), do: metadata

  defp maybe_put_context(metadata, _key, nil), do: metadata
  defp maybe_put_context(metadata, key, value), do: Map.put(metadata, key, value)

  defp issue_value(%{} = issue, key), do: Map.get(issue, key)
  defp issue_value(_issue, _key), do: nil
end
