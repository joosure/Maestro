defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Retention do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Clock
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.Error
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.State
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Registry.StorageSync

  @spec prune_expired(State.t(), keyword()) :: {:ok, State.t()} | {:error, map()}
  def prune_expired(%State{target_ttl_ms: nil} = state, _opts), do: {:ok, state}

  def prune_expired(%State{target_ttl_ms: ttl_ms} = state, opts) when is_integer(ttl_ms) do
    with {:ok, now_ms} <- Clock.now_ms(opts) do
      {expired_issue_ids, targets} =
        Enum.reduce(state.targets, {[], %{}}, fn {issue_id, %KnownTarget{} = target}, {expired_issue_ids, targets} ->
          if target_age_ms(target, now_ms) >= ttl_ms do
            {[issue_id | expired_issue_ids], targets}
          else
            {expired_issue_ids, Map.put(targets, issue_id, target)}
          end
        end)

      case StorageSync.delete_targets(state, expired_issue_ids) do
        :ok -> {:ok, %{state | targets: targets}}
        {:error, reason} -> {:error, Error.storage_delete_failed(:ttl_prune, reason)}
      end
    end
  end

  @spec enforce_target_limit(State.t()) :: {:ok, State.t()} | {:error, map()}
  def enforce_target_limit(%State{max_targets: max_targets} = state) when map_size(state.targets) <= max_targets,
    do: {:ok, state}

  def enforce_target_limit(%State{max_targets: max_targets} = state) do
    overflow_count = map_size(state.targets) - max_targets

    evicted_issue_ids =
      state.targets
      |> Map.values()
      |> Enum.sort_by(&target_sort_ms/1, :asc)
      |> Enum.take(overflow_count)
      |> Enum.map(& &1.issue_id)

    case StorageSync.delete_targets(state, evicted_issue_ids) do
      :ok -> {:ok, %{state | targets: Map.drop(state.targets, evicted_issue_ids)}}
      {:error, reason} -> {:error, Error.storage_delete_failed(:max_target_evict, reason)}
    end
  end

  defp target_age_ms(%KnownTarget{} = target, now_ms) when is_integer(now_ms) do
    last_seen_ms = target.updated_at_ms || target.registered_at_ms || now_ms
    now_ms - last_seen_ms
  end

  defp target_sort_ms(%KnownTarget{} = target), do: target.updated_at_ms || target.registered_at_ms || 0
end
