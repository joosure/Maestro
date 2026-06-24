defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Tracker do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ExternalReferenceContract, as: ExternalReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @change_proposal_key Evidence.change_proposal_key()
  @status_key Evidence.status_key()
  @source_key Evidence.source_key()
  @id_key Evidence.id_key()
  @url_key Evidence.url_key()
  @provider_kind_key Evidence.provider_kind_key()
  @repository_key Evidence.repository_key()
  @linked_to_tracker_key Evidence.linked_to_tracker_key()
  @observed_at_key Evidence.observed_at_key()
  @linked_status Values.linked_status()
  @tracker_observed_source Values.tracker_observed_source()

  @payload_attachment_key "attachment"
  @payload_id_key "id"
  @payload_url_key "url"
  @payload_provider_kind_key "provider_kind"
  @payload_repository_key "repository"
  @payload_linked_to_tracker_key "linked_to_tracker"

  @spec observation(term(), term()) :: map()
  def observation(arguments, payload) do
    if change_proposal_reference?(arguments) do
      attachment = Normalization.payload_value(payload, @payload_attachment_key) || %{}

      external_reference =
        Normalization.payload_value(payload, ExternalReference.external_reference_key()) || Normalization.payload_value(payload, ExternalReference.external_reference_snake_key()) || %{}

      metadata = Normalization.value(arguments, ExternalReference.metadata_key()) || %{}

      canonical_observation(%{
        @payload_id_key =>
          Normalization.string_value(arguments, ExternalReference.external_id_key()) || Normalization.string_value(external_reference, ExternalReference.external_id_camel_key()) ||
            Normalization.string_value(attachment, @payload_id_key),
        @payload_url_key =>
          Normalization.string_value(external_reference, @payload_url_key) ||
            Normalization.string_value(attachment, @payload_url_key) ||
            Normalization.string_value(arguments, @payload_url_key),
        @payload_provider_kind_key => Normalization.string_value(arguments, ExternalReference.provider_kind_key()) || Normalization.string_value(metadata, ExternalReference.provider_kind_key()),
        @payload_repository_key => Normalization.string_value(metadata, @payload_repository_key),
        @payload_linked_to_tracker_key => true
      })
    else
      %{}
    end
  end

  @spec canonical_observation(map()) :: map()
  def canonical_observation(change_proposal) when is_map(change_proposal) do
    %{
      @change_proposal_key =>
        Normalization.compact(%{
          @status_key => @linked_status,
          @source_key => @tracker_observed_source,
          @url_key => Normalization.string_value(change_proposal, @payload_url_key),
          @id_key => Normalization.string_value(change_proposal, @payload_id_key),
          @provider_kind_key => Normalization.string_value(change_proposal, @payload_provider_kind_key),
          @repository_key => Normalization.string_value(change_proposal, @payload_repository_key),
          @linked_to_tracker_key => Normalization.value(change_proposal, @payload_linked_to_tracker_key) == true,
          @observed_at_key => Normalization.generated_at()
        })
    }
  end

  defp change_proposal_reference?(arguments), do: Normalization.string_value(arguments, ExternalReference.reference_kind_key()) == ExternalReference.change_proposal_kind()
end
