defmodule SymphonyElixir.Orchestrator.WorkerHosts do
  @moduledoc false

  alias SymphonyElixir.Config

  @spec select_host(map(), String.t() | nil) :: String.t() | nil | :no_worker_capacity
  def select_host(state, preferred_worker_host) when is_map(state) do
    settings = Config.settings!()

    case settings.worker.ssh_hosts do
      [] ->
        if local_slots_available?(state, settings) do
          nil
        else
          :no_worker_capacity
        end

      hosts ->
        available_hosts = Enum.filter(hosts, &host_slots_available?(state, &1, settings))

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
    host_slots_available?(state, worker_host, Config.settings!())
  end

  def host_slots_available?(_state, _worker_host), do: false

  @spec local_slots_available?(map()) :: boolean()
  def local_slots_available?(state) when is_map(state) do
    local_slots_available?(state, Config.settings!())
  end

  def local_slots_available?(_state), do: true

  defp local_slots_available?(state, settings) when is_map(state) and is_map(settings) do
    case worker_setting(settings, :max_concurrent_local_agents) do
      limit when is_integer(limit) and limit > 0 ->
        worker_daemon_runtime?(settings) or local_running_count(running_entries(state)) < limit

      _ ->
        true
    end
  end

  defp host_slots_available?(state, worker_host, settings)
       when is_map(state) and is_binary(worker_host) and is_map(settings) do
    case worker_setting(settings, :max_concurrent_agents_per_host) do
      limit when is_integer(limit) and limit > 0 ->
        running_host_count(running_entries(state), worker_host) < limit

      _ ->
        true
    end
  end

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

  defp local_running_count(running) when is_map(running) do
    Enum.count(running, fn
      {_issue_id, entry} when is_map(entry) -> local_running_entry?(entry)
      _other -> false
    end)
  end

  defp local_running_entry?(%{worker_placement: placement}) when placement in ["worker_daemon", :worker_daemon],
    do: false

  defp local_running_entry?(entry) when is_map(entry) do
    worker_daemon_endpoint = Map.get(entry, :worker_daemon_endpoint) || Map.get(entry, "worker_daemon_endpoint")
    worker_host = Map.get(entry, :worker_host) || Map.get(entry, "worker_host")

    is_nil(worker_daemon_endpoint) and (is_nil(worker_host) or worker_host == "")
  end

  defp worker_daemon_runtime?(settings) when is_map(settings) do
    case settings |> Map.get(:runtime, %{}) |> Map.get(:agent, %{}) |> Map.get(:placement) do
      "worker_daemon" -> true
      :worker_daemon -> true
      _placement -> false
    end
  end

  defp worker_setting(settings, key) when is_map(settings) and is_atom(key) do
    settings
    |> Map.get(:worker, %{})
    |> Map.get(key)
  end

  defp running_entries(%{running: running}) when is_map(running), do: running
  defp running_entries(_state), do: %{}
end
