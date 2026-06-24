defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.Events do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Emitter
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.Options

  @spec candidate_enqueue_dropped(KnownTarget.t(), map(), Options.t()) :: :ok | {:error, term()}
  def candidate_enqueue_dropped(%KnownTarget{} = target, %{dropped_count: dropped_count} = enqueue_result, %Options{} = options)
      when is_integer(dropped_count) and dropped_count > 0 do
    emit(
      options,
      :warning,
      Contract.event(:candidate_enqueue_dropped),
      Map.merge(enqueue_result, target_fields(target))
    )
  end

  def candidate_enqueue_dropped(_target, _enqueue_result, _options), do: :ok

  defp emit(%Options{emit_event_fn: nil}, level, event, fields) do
    Emitter.emit(level, event, event_fields(fields), [])
    |> normalize_emit_result()
  end

  defp emit(%Options{emit_event_fn: emit_event_fn}, level, event, fields) when is_function(emit_event_fn, 3) do
    emit_event_fn
    |> safe_emit(level, event, event_fields(fields))
    |> normalize_emit_result()
  end

  defp safe_emit(emit_event_fn, level, event, fields) do
    emit_event_fn.(level, event, fields)
  rescue
    error -> {:error, {:known_target_registration_event_failed, Diagnostics.exception(error)}}
  catch
    kind, reason -> {:error, {:known_target_registration_event_failed, Diagnostics.caught(kind, reason)}}
  end

  defp normalize_emit_result({:error, _reason} = error), do: error
  defp normalize_emit_result(_result), do: :ok

  defp event_fields(fields) when is_map(fields) do
    Map.merge(
      %{
        Fields.component() => Contract.component(),
        :producer => Contract.producer(:known_target_registry)
      },
      fields
    )
  end

  defp target_fields(%KnownTarget{} = target) do
    %{
      Fields.issue_id() => target.issue_id,
      Fields.tracker_kind() => target.tracker_kind,
      Fields.repo_provider_kind() => target.repo_provider_kind,
      Fields.repository() => target.repository,
      Fields.change_proposal_number() => target.number,
      Fields.change_proposal_url() => target.url,
      Fields.change_proposal_branch() => target.branch
    }
  end
end
