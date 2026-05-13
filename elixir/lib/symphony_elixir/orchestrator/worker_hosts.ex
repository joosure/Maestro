defmodule SymphonyElixir.Orchestrator.WorkerHosts do
  @moduledoc false

  alias SymphonyElixir.Config

  @spec select_host(map(), String.t() | nil) :: String.t() | nil | :no_worker_capacity
  def select_host(state, preferred_worker_host) when is_map(state) do
    case Config.settings!().worker.ssh_hosts do
      [] ->
        nil

      hosts ->
        available_hosts = Enum.filter(hosts, &host_slots_available?(state, &1))

        cond do
          available_hosts == [] ->
            :no_worker_capacity

          preferred_host_available?(preferred_worker_host, available_hosts) ->
            preferred_worker_host

          true ->
            least_loaded_host(state, available_hosts)
        end
    end
  end

  def select_host(_state, _preferred_worker_host), do: nil

  @spec slots_available?(map(), String.t() | nil) :: boolean()
  def slots_available?(state, preferred_worker_host) when is_map(state) do
    select_host(state, preferred_worker_host) != :no_worker_capacity
  end

  def slots_available?(_state, _preferred_worker_host), do: true

  @spec host_slots_available?(map(), String.t()) :: boolean()
  def host_slots_available?(state, worker_host) when is_map(state) and is_binary(worker_host) do
    case Config.settings!().worker.max_concurrent_agents_per_host do
      limit when is_integer(limit) and limit > 0 ->
        running_host_count(running_entries(state), worker_host) < limit

      _ ->
        true
    end
  end

  def host_slots_available?(_state, _worker_host), do: false

  defp preferred_host_available?(preferred_worker_host, hosts)
       when is_binary(preferred_worker_host) and is_list(hosts) do
    preferred_worker_host != "" and preferred_worker_host in hosts
  end

  defp preferred_host_available?(_preferred_worker_host, _hosts), do: false

  defp least_loaded_host(state, hosts) when is_list(hosts) do
    running = running_entries(state)

    hosts
    |> Enum.with_index()
    |> Enum.min_by(fn {host, index} ->
      {running_host_count(running, host), index}
    end)
    |> elem(0)
  end

  defp running_host_count(running, worker_host) when is_map(running) and is_binary(worker_host) do
    Enum.count(running, fn
      {_issue_id, %{worker_host: ^worker_host}} -> true
      _ -> false
    end)
  end

  defp running_entries(%{running: running}) when is_map(running), do: running
  defp running_entries(_state), do: %{}
end
