defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.ObservationProjection do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget.Observation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts

  @spec attrs(Facts.t() | map()) :: map()
  def attrs(%Facts{} = facts), do: facts |> facts_map() |> Observation.attrs()
  def attrs(facts) when is_map(facts), do: Observation.attrs(facts)

  @spec signature(Facts.t() | map()) :: map()
  def signature(%Facts{} = facts), do: facts |> facts_map() |> Observation.signature()
  def signature(facts) when is_map(facts), do: Observation.signature(facts)

  defp facts_map(%Facts{} = facts) do
    %{
      Fields.provider_state() => facts.provider_state,
      Fields.review_summary() => facts.review_summary,
      Fields.check_summary() => facts.check_summary,
      Fields.mergeability_summary() => facts.mergeability_summary,
      Fields.unresolved_actionable_feedback() => facts.unresolved_actionable_feedback?,
      Fields.number() => facts.number,
      Fields.url() => facts.url,
      Fields.branch() => facts.branch,
      Fields.head_sha() => facts.head_sha,
      Fields.error() => facts.error,
      Fields.retryable() => facts.retryable?,
      Fields.observed_at() => facts.observed_at
    }
  end
end
