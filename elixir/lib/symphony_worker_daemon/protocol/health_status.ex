defmodule SymphonyWorkerDaemon.Protocol.HealthStatus do
  @moduledoc """
  Stable Worker Daemon health status values shared by server and client.
  """

  @ready "ready"
  @degraded "degraded"
  @unavailable "unavailable"

  @default_accepted_statuses [@ready]

  @spec ready() :: String.t()
  def ready, do: @ready

  @spec degraded() :: String.t()
  def degraded, do: @degraded

  @spec unavailable() :: String.t()
  def unavailable, do: @unavailable

  @spec default_accepted_statuses() :: [String.t()]
  def default_accepted_statuses, do: @default_accepted_statuses

  @spec normalize(term()) :: String.t()
  def normalize(status) when is_binary(status), do: status
  def normalize(status) when is_atom(status), do: Atom.to_string(status)
  def normalize(_status), do: @unavailable

  @spec aggregate(term(), term()) :: String.t()
  def aggregate(capacity_status, ledger_status) do
    capacity_status = normalize(capacity_status)
    ledger_status = normalize(ledger_status)

    cond do
      capacity_status == @unavailable or ledger_status == @unavailable -> @unavailable
      ledger_status == @degraded -> @degraded
      true -> capacity_status
    end
  end
end
