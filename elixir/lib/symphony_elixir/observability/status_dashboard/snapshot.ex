defmodule SymphonyElixir.Observability.StatusDashboard.Snapshot do
  @moduledoc false

  alias SymphonyElixir.Observability.StatusDashboard.{Drilldown, Throughput}
  alias SymphonyElixir.Orchestrator

  @spec with_samples([{integer(), integer()}], integer()) :: {term(), [{integer(), integer()}]}
  def with_samples(token_samples, now_ms) do
    case payload() do
      {:ok, %{running: running, retrying: retrying} = snapshot} ->
        agent_totals = Map.get(snapshot, :agent_totals) || %{}
        total_tokens = Map.get(agent_totals, :total_tokens, 0)

        {
          {:ok,
           %{
             running: running,
             retrying: retrying,
             agent_totals: agent_totals,
             agent_rate_limits: Map.get(snapshot, :agent_rate_limits),
             polling: Map.get(snapshot, :polling),
             drilldown: Map.get(snapshot, :drilldown, [])
           }},
          Throughput.update_token_samples(token_samples, now_ms, total_tokens)
        }

      :error ->
        {
          :error,
          Throughput.prune_samples(token_samples, now_ms)
        }
    end
  end

  @spec total_tokens(term()) :: non_neg_integer()
  def total_tokens({:ok, snapshot}) when is_map(snapshot) do
    totals = Map.get(snapshot, :agent_totals) || %{}
    total_tokens_from(totals)
  end

  def total_tokens(_snapshot_data), do: 0

  @spec polling(term()) :: map() | nil
  def polling({:ok, snapshot}) when is_map(snapshot), do: Map.get(snapshot, :polling)
  def polling(_snapshot_data), do: nil

  defp payload do
    if Process.whereis(Orchestrator) do
      case Orchestrator.snapshot() do
        %{
          running: running,
          retrying: retrying
        } = snapshot
        when is_list(running) and is_list(retrying) ->
          {:ok,
           %{
             running: running,
             retrying: retrying,
             agent_totals: Map.get(snapshot, :agent_totals),
             agent_rate_limits: Map.get(snapshot, :agent_rate_limits),
             polling: Map.get(snapshot, :polling),
             drilldown: Drilldown.payload(running, retrying)
           }}

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp total_tokens_from(%{} = totals), do: Map.get(totals, :total_tokens, 0)
  defp total_tokens_from(_totals), do: 0
end
