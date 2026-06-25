defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.RuntimeTopology do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher

  @topology_singleton "singleton"
  @ready_status "ready"
  @blocked_status "blocked"

  @type readiness :: %{
          required(:ready?) => boolean(),
          required(:status) => String.t(),
          required(:topology) => String.t() | nil,
          required(:process_local_state) => boolean(),
          required(:writers) => [map()],
          optional(:reason) => atom(),
          optional(:value_type) => atom()
        }

  @spec readiness(term()) :: readiness()
  def readiness(opts \\ [])

  def readiness(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> normalize_topology()
      |> build_readiness(opts)
    else
      blocked(nil, [], :options_not_keyword, Diagnostics.type_atom(opts))
    end
  end

  def readiness(opts), do: blocked(nil, [], :options_not_keyword, Diagnostics.type_atom(opts))

  defp build_readiness({:ok, @topology_singleton = topology}, opts) do
    writers = Enum.map(writer_specs(opts), fn {id, server} -> writer_status(id, server) end)

    case Enum.find(writers, &Map.has_key?(&1, :reason)) do
      nil ->
        %{
          ready?: true,
          status: @ready_status,
          topology: topology,
          process_local_state: true,
          ownership: "single_active_writer_per_node",
          writers: writers
        }

      %{reason: reason} = writer ->
        blocked(topology, writers, reason, Map.get(writer, :value_type))
    end
  end

  defp build_readiness({:error, reason, value_type}, _opts), do: blocked(nil, [], reason, value_type)

  defp normalize_topology(opts) do
    case Keyword.fetch(opts, :topology) do
      {:ok, :singleton} -> {:ok, @topology_singleton}
      {:ok, @topology_singleton} -> {:ok, @topology_singleton}
      {:ok, value} -> {:error, :singleton_topology_required, Diagnostics.type_atom(value)}
      :error -> {:error, :singleton_topology_required, nil}
    end
  end

  defp writer_specs(opts) do
    [
      candidate_inbox: Keyword.get(opts, :inbox, Inbox),
      known_target_registry: Keyword.get(opts, :known_target_registry, KnownTarget.Registry),
      known_target_watcher: Keyword.get(opts, :watcher, Watcher)
    ]
  end

  defp writer_status(id, server) when is_atom(server) and not is_nil(server) do
    case Process.whereis(server) do
      pid when is_pid(pid) ->
        %{
          id: Atom.to_string(id),
          server: inspect(server),
          registered?: true,
          alive?: true,
          ownership: "process_local_registered_singleton"
        }

      _missing ->
        %{
          id: Atom.to_string(id),
          server: inspect(server),
          registered?: true,
          alive?: false,
          reason: :writer_unavailable
        }
    end
  end

  defp writer_status(id, server) when is_pid(server) do
    %{
      id: Atom.to_string(id),
      server: "pid",
      registered?: false,
      alive?: Process.alive?(server),
      reason: :writer_not_registered
    }
  end

  defp writer_status(id, server) do
    %{
      id: Atom.to_string(id),
      server: "invalid",
      registered?: false,
      alive?: false,
      reason: :invalid_writer_server,
      value_type: Diagnostics.type_atom(server)
    }
  end

  defp blocked(topology, writers, reason, nil) do
    %{
      ready?: false,
      status: @blocked_status,
      topology: topology,
      process_local_state: true,
      reason: reason,
      writers: writers
    }
  end

  defp blocked(topology, writers, reason, value_type) do
    topology
    |> blocked(writers, reason, nil)
    |> Map.put(:value_type, value_type)
  end
end
