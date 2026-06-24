defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.ChangeProposalFields do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Reference, as: KnownTargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Decision
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.{Diagnostics, Fields}
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts

  @spec reference(map()) :: map()
  def reference(reference) when is_map(reference) do
    %{
      Fields.change_proposal_number() => reference_value(reference, :number),
      Fields.change_proposal_url() => reference_value(reference, :url),
      Fields.change_proposal_branch() => reference_value(reference, :branch)
    }
  end

  @spec facts(Facts.t()) :: map()
  def facts(%Facts{} = facts) do
    %{
      Fields.repo_provider_kind() => facts.provider_kind,
      Fields.repository() => facts.repository,
      Fields.change_proposal_number() => facts.number,
      Fields.change_proposal_url() => facts.url,
      Fields.change_proposal_branch() => facts.branch,
      Fields.head_sha() => facts.head_sha,
      Fields.provider_state() => facts.provider_state,
      Fields.review_summary() => facts.review_summary,
      Fields.check_summary() => facts.check_summary,
      Fields.mergeability_summary() => facts.mergeability_summary,
      Fields.retryable() => facts.retryable?,
      Fields.error() => Diagnostics.error(facts.error)
    }
  end

  @spec decision(Decision.t()) :: map()
  def decision(%Decision{} = decision) do
    %{
      Fields.decision() => decision.action,
      Fields.reason() => decision.reason
    }
  end

  @spec transition_facts(Facts.t()) :: map()
  def transition_facts(%Facts{} = facts) do
    %{
      Fields.repo_provider_kind() => facts.provider_kind,
      Fields.change_proposal_number() => facts.number,
      Fields.change_proposal_url() => facts.url,
      Fields.head_sha() => facts.head_sha
    }
  end

  @spec transition_extra(map()) :: map()
  def transition_extra(fields) when is_map(fields) do
    case Map.fetch(fields, Fields.skip_reason()) do
      {:ok, reason} -> Map.put(fields, Fields.skip_reason(), Contract.reason_name(reason))
      :error -> fields
    end
  end

  defp reference_value(%KnownTargetReference{} = reference, :number), do: reference.number
  defp reference_value(%KnownTargetReference{} = reference, :url), do: reference.url
  defp reference_value(%KnownTargetReference{} = reference, :branch), do: reference.branch
  defp reference_value(reference, key) when is_map(reference) and is_atom(key), do: Map.get(reference, key)
end
