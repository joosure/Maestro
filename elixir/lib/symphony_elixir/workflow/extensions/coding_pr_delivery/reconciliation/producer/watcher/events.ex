defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Watcher.Events do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.Diagnostics

  @spec candidate_enqueue_dropped(KnownTarget.t(), map(), map()) :: :ok
  def candidate_enqueue_dropped(%KnownTarget{} = target, enqueue_result, context) when is_map(enqueue_result) do
    emit(
      context,
      :warning,
      Contract.event(:candidate_enqueue_dropped),
      Map.merge(target_fields(target), Map.put(enqueue_result, :producer, Contract.producer(:known_target_watcher)))
    )
  end

  @spec watcher_failed(KnownTarget.t(), map(), map()) :: :ok
  def watcher_failed(%KnownTarget{} = target, context, fields) when is_map(context) and is_map(fields) do
    emit(
      context,
      :warning,
      Contract.event(:known_target_watcher_failed),
      Map.merge(target_fields(target), fields)
    )
  end

  @spec command_failure(String.t(), term(), map()) :: :ok
  def command_failure(issue_id, reason, context) when is_binary(issue_id) and is_map(context) do
    emit(
      context,
      :warning,
      Contract.event(:known_target_watcher_failed),
      %{
        issue_id: issue_id,
        failure_reason: :runtime_command_failed
      }
      |> Map.merge(Diagnostics.reason_fields(reason))
    )
  end

  defp emit(context, level, event, fields) when is_map(context) and is_atom(level) and is_atom(event) and is_map(fields) do
    context.emit_event_fn.(
      level,
      event,
      Map.merge(
        %{
          component: Contract.component(),
          producer: Contract.producer(:known_target_watcher)
        },
        normalize_event_fields(fields)
      )
    )
  end

  defp normalize_event_fields(fields) when is_map(fields) do
    case Map.fetch(fields, :failure_reason) do
      {:ok, reason} -> Map.put(fields, :failure_reason, Contract.reason_name(reason))
      :error -> fields
    end
  end

  defp target_fields(%KnownTarget{} = target) do
    %{
      issue_id: target.issue_id,
      tracker_kind: target.tracker_kind,
      repo_provider_kind: target.repo_provider_kind,
      repository: target.repository,
      change_proposal_number: target.number,
      change_proposal_url: target.url,
      change_proposal_branch: target.branch
    }
  end
end
