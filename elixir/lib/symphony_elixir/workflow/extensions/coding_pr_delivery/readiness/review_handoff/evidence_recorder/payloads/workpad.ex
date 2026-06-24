defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Workpad do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder.Payloads.Normalization
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  @workpad_key Evidence.workpad_key()
  @status_key Evidence.status_key()
  @source_key Evidence.source_key()
  @workpad_id_key Evidence.workpad_id_key()
  @url_key Evidence.url_key()
  @updated_at_key Evidence.updated_at_key()
  @typed_tool_observed_source Values.typed_tool_observed_source()
  @created_status Values.created_status()
  @updated_status Values.updated_status()

  @payload_status_key "status"
  @payload_id_key "id"
  @payload_url_key "url"
  @payload_comment_key "comment"
  @payload_created_key "created"
  @payload_updated_key "updated"

  @spec canonical_observation(map()) :: map()
  def canonical_observation(workpad) when is_map(workpad) do
    %{
      @workpad_key =>
        Normalization.compact(%{
          @status_key => Normalization.string_value(workpad, @payload_status_key) || @updated_status,
          @source_key => @typed_tool_observed_source,
          @workpad_id_key => Normalization.string_value(workpad, @payload_id_key),
          @url_key => Normalization.string_value(workpad, @payload_url_key),
          @updated_at_key => Normalization.generated_at()
        })
    }
  end

  @spec observation(term()) :: map()
  def observation(payload) do
    case Normalization.payload_value(payload, @payload_comment_key) do
      comment when is_map(comment) ->
        canonical_observation(%{
          @payload_status_key => workpad_write_status(comment),
          @payload_id_key => Normalization.string_value(comment, @payload_id_key),
          @payload_url_key => Normalization.string_value(comment, @payload_url_key)
        })

      _comment ->
        %{}
    end
  end

  defp workpad_write_status(%{@payload_created_key => true}), do: @created_status
  defp workpad_write_status(%{@payload_updated_key => true}), do: @updated_status
  defp workpad_write_status(_comment), do: @updated_status
end
