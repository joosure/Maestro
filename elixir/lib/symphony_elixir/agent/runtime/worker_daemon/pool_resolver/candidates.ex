defmodule SymphonyElixir.Agent.Runtime.WorkerDaemon.PoolResolver.Candidates do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime.Target
  alias SymphonyElixir.Agent.Runtime.WorkerDaemon.Endpoint

  @endpoint_env "SYMPHONY_WORKER_DAEMON_ENDPOINTS"

  @spec build(Target.t(), keyword()) :: [map()]
  def build(%Target{} = target, opts) when is_list(opts) do
    []
    |> Kernel.++(source_candidates(Keyword.get(opts, :worker_daemon_endpoints), "opts.worker_daemon_endpoints"))
    |> Kernel.++(pool_candidates(target.worker_pool, Keyword.get(opts, :worker_daemon_pools), "opts.worker_daemon_pools"))
    |> Kernel.++(source_candidates(Application.get_env(:symphony_elixir, :worker_daemon_endpoints), "app.worker_daemon_endpoints"))
    |> Kernel.++(pool_candidates(target.worker_pool, Application.get_env(:symphony_elixir, :worker_daemon_pools), "app.worker_daemon_pools"))
    |> Kernel.++(env_candidates())
    |> unique()
  end

  @spec unique([map()]) :: [map()]
  def unique(candidates) when is_list(candidates) do
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

  defp source_candidates(nil, _source), do: []

  defp source_candidates(value, source) when is_binary(value) do
    value
    |> split_endpoints()
    |> source_candidates(source)
  end

  defp source_candidates(values, source) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_candidate(&1, source))
  end

  defp source_candidates(value, source), do: normalize_candidate(value, source)

  defp pool_candidates(nil, _pools, _source), do: []
  defp pool_candidates(_worker_pool, nil, _source), do: []

  defp pool_candidates(worker_pool, pools, source) when is_map(pools) do
    pools
    |> Enum.find_value([], fn {pool_name, entries} ->
      if to_string(pool_name) == worker_pool do
        source_candidates(entries, source <> "." <> worker_pool)
      else
        nil
      end
    end)
  end

  defp pool_candidates(worker_pool, pools, source) when is_list(pools) do
    pools
    |> Map.new()
    |> pool_candidates(worker_pool, source)
  rescue
    ArgumentError -> []
  end

  defp pool_candidates(_worker_pool, _pools, _source), do: []

  defp env_candidates do
    @endpoint_env
    |> System.get_env()
    |> source_candidates("env." <> @endpoint_env)
  end

  defp normalize_candidate(value, source) when is_binary(value) do
    case normalize_endpoint(value) do
      nil -> []
      endpoint -> [%{endpoint: endpoint, source: source}]
    end
  end

  defp normalize_candidate(value, source) when is_map(value) do
    endpoint = map_string(value, ["endpoint", :endpoint, "url", :url])

    case normalize_endpoint(endpoint) do
      nil ->
        []

      endpoint ->
        [
          %{
            endpoint: endpoint,
            worker_id: map_string(value, ["worker_id", :worker_id]),
            endpoint_id: map_string(value, ["id", :id, "endpoint_id", :endpoint_id]),
            source: source
          }
          |> compact_map()
        ]
    end
  end

  defp normalize_candidate(value, source) when is_list(value) do
    value
    |> Map.new()
    |> normalize_candidate(source)
  rescue
    ArgumentError -> []
  end

  defp normalize_candidate(_value, _source), do: []

  defp split_endpoints(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp normalize_endpoint(value) do
    case Endpoint.normalize_validated(value) do
      {:ok, endpoint} -> endpoint
      {:error, _reason} -> nil
    end
  end

  defp map_string(map, keys) when is_map(map) and is_list(keys) do
    keys
    |> Enum.find_value(fn key -> Map.get(map, key) end)
    |> normalize_optional_string()
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

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
