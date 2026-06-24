defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.TargetInspector do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.ObservationProjection
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Commands
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Result

  @spec inspect_target(KnownTarget.t(), Result.t(), map()) :: Result.t()
  def inspect_target(%KnownTarget{} = target, result, context) do
    facts = context.facts_fn.(context.repo, KnownTarget.reference(target), context.provider_facts_opts)
    signature = ObservationProjection.signature(facts)
    changed? = target.last_observed_signature != signature
    due? = enqueue_due?(target, context.now_ms, context.enqueue_unchanged_after_ms)
    should_enqueue? = changed? or due?

    {enqueued?, enqueue_error?} =
      if should_enqueue? do
        enqueue_known_target(target, context)
      else
        {false, false}
      end

    observation_attrs =
      facts
      |> ObservationProjection.attrs()
      |> maybe_put(Fields.last_enqueued_at_ms(), if(enqueued?, do: context.now_ms, else: nil))

    update_result = update_observation(target, observation_attrs, context)
    Commands.release_blocked_issue_if_changed(target, changed?, context)

    update_error? = emit_update_failure(update_result, target, context)

    Result.record_success(result, enqueued?, changed?, due?, update_error?, enqueue_error?)
  rescue
    error ->
      Events.watcher_failed(target, context, Diagnostics.reason_fields(error))
      Result.record_error(result)
  end

  defp enqueue_known_target(%KnownTarget{} = target, context) when is_map(context) do
    case context.enqueue_fn.([target.issue_id], server: context.inbox) do
      {:ok, %{dropped_count: dropped_count} = enqueue_result} when is_integer(dropped_count) and dropped_count > 0 ->
        Events.candidate_enqueue_dropped(target, enqueue_result, context)
        {false, true}

      {:ok, enqueue_result} when is_map(enqueue_result) ->
        {Map.get(enqueue_result, :accepted_count, 0) + Map.get(enqueue_result, :duplicate_count, 0) > 0, false}

      {:error, reason} ->
        Events.watcher_failed(
          target,
          context,
          Map.merge(Diagnostics.reason_fields(reason), %{failure_reason: :candidate_inbox_unavailable})
        )

        {false, true}
    end
  end

  defp update_observation(%KnownTarget{} = target, observation_attrs, context) when is_map(context) do
    context.registry_module.update_observation(
      target.issue_id,
      observation_attrs,
      server: context.registry,
      now_ms: context.now_ms
    )
  end

  defp emit_update_failure({:ok, _updated_target}, _target, _context), do: false

  defp emit_update_failure({:error, reason}, %KnownTarget{} = target, context) do
    Events.watcher_failed(
      target,
      context,
      Map.merge(Diagnostics.reason_fields(reason), %{failure_reason: :known_target_update_failed})
    )

    true
  end

  defp emit_update_failure(_result, _target, _context), do: false

  defp enqueue_due?(%KnownTarget{last_enqueued_at_ms: nil}, _now_ms, _enqueue_unchanged_after_ms), do: true

  defp enqueue_due?(%KnownTarget{last_enqueued_at_ms: last_enqueued_at_ms}, now_ms, enqueue_unchanged_after_ms)
       when is_integer(last_enqueued_at_ms) and is_integer(now_ms) and is_integer(enqueue_unchanged_after_ms) do
    now_ms - last_enqueued_at_ms >= enqueue_unchanged_after_ms
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
