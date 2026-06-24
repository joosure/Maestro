defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Payload do
  @moduledoc """
  Raw typed-tool payload normalization for Coding PR Delivery evidence binding.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ExternalReferenceContract, as: ExternalReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Payload, as: PayloadContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.RawPayload, as: RawPayloadContract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.StructuredExecutionPlan.EvidenceBinding.Contract.Status, as: StatusContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus.Contract, as: CheckStatusContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput

  @spec creation_payload(term(), term(), term()) :: {:ok, map()} | :unknown
  def creation_payload(source_kind, source_context, payload) do
    data = data(payload)

    with {:ok, proposal} <- change_proposal(data) do
      {:ok,
       proposal
       |> proposal_payload()
       |> Map.put(PayloadContract.action_key(), RawInput.string_value(data, RawPayloadContract.action_key()))
       |> Map.put(PayloadContract.provider_kind_key(), provider_kind(source_kind, source_context))
       |> RawInput.compact()}
    end
  end

  @spec snapshot_payload(term(), term(), term()) :: {:ok, map()} | :unknown
  def snapshot_payload(source_kind, source_context, payload) do
    data = data(payload)

    with {:ok, proposal} <- change_proposal(data) do
      {:ok,
       proposal
       |> proposal_payload()
       |> Map.put(PayloadContract.exists_key(), Map.get(data, RawPayloadContract.exists_key()))
       |> Map.put(PayloadContract.provider_kind_key(), provider_kind(source_kind, source_context))
       |> put_checks_summary(Map.get(data, RawPayloadContract.checks_key()))
       |> put_discussion_summary(Map.get(data, RawPayloadContract.discussion_key()))
       |> RawInput.compact()}
    end
  end

  @spec checks_payload(term()) :: {:ok, map()} | :unknown
  def checks_payload(payload) do
    with {:ok, checks} <- payload |> data() |> checks() do
      {:ok,
       RawInput.compact(%{
         PayloadContract.status_key() => CheckStatus.status(checks),
         PayloadContract.head_sha_key() =>
           RawInput.string_value(checks, RawPayloadContract.head_sha_camel_key()) ||
             RawInput.string_value(checks, RawPayloadContract.head_sha_key()),
         CheckStatusContract.summary_key() => Map.get(checks, CheckStatusContract.summary_key()),
         PayloadContract.run_count_key() => checks |> Map.get(CheckStatusContract.runs_key()) |> RawInput.list_length()
       })}
    end
  end

  @spec discussion_payload(term()) :: {:ok, map()} | :unknown
  def discussion_payload(payload) do
    with {:ok, discussion} <- payload |> data() |> discussion() do
      actionable_count = actionable_count(discussion)

      {:ok,
       RawInput.compact(%{
         PayloadContract.status_key() => discussion_status(actionable_count),
         PayloadContract.actionable_count_key() => actionable_count
       })}
    end
  end

  @spec tracker_attachment_payload(term(), term(), term()) :: {:ok, map()} | :unknown
  def tracker_attachment_payload(source_kind, arguments, payload) do
    data = data(payload)

    with {:ok, attachment} <- attachment(data),
         {:ok, external_reference} <- external_reference(data) do
      metadata = RawInput.value(arguments, ExternalReference.metadata_key()) || %{}

      {:ok,
       RawInput.compact(%{
         PayloadContract.tracker_kind_key() => source_kind && to_string(source_kind),
         PayloadContract.attachment_id_key() => RawInput.string_value(attachment, RawPayloadContract.id_key()),
         PayloadContract.url_key() =>
           RawInput.string_value(external_reference, RawPayloadContract.url_key()) ||
             RawInput.string_value(attachment, RawPayloadContract.url_key()) ||
             RawInput.string_value(arguments, RawPayloadContract.url_key()),
         PayloadContract.change_proposal_id_key() =>
           RawInput.string_value(arguments, ExternalReference.external_id_key()) ||
             RawInput.string_value(external_reference, ExternalReference.external_id_camel_key()) ||
             RawInput.string_value(attachment, RawPayloadContract.id_key()),
         PayloadContract.repo_provider_kind_key() =>
           RawInput.string_value(arguments, ExternalReference.provider_kind_key()) ||
             RawInput.string_value(metadata, ExternalReference.provider_kind_key()),
         PayloadContract.repository_key() => RawInput.string_value(metadata, RawPayloadContract.repository_key()),
         PayloadContract.linked_to_tracker_key() => true
       })}
    end
  end

  @spec change_proposal_reference?(term()) :: boolean()
  def change_proposal_reference?(arguments) do
    RawInput.string_value(arguments, ExternalReference.reference_kind_key()) == ExternalReference.change_proposal_kind()
  end

  defp data(payload) when is_map(payload), do: Map.get(payload, RawPayloadContract.data_key(), %{}) || %{}
  defp data(_payload), do: %{}

  defp change_proposal(data) when is_map(data) do
    case Map.get(data, RawPayloadContract.change_proposal_key()) do
      proposal when is_map(proposal) and map_size(proposal) > 0 -> {:ok, proposal}
      _proposal -> :unknown
    end
  end

  defp change_proposal(_data), do: :unknown

  defp checks(data) when is_map(data) do
    case Map.get(data, RawPayloadContract.checks_key()) do
      checks when is_map(checks) -> {:ok, checks}
      _checks -> :unknown
    end
  end

  defp checks(_data), do: :unknown

  defp discussion(data) when is_map(data) do
    case Map.get(data, RawPayloadContract.discussion_key()) do
      discussion when is_map(discussion) -> {:ok, discussion}
      _discussion -> :unknown
    end
  end

  defp discussion(_data), do: :unknown

  defp attachment(data) when is_map(data) do
    case Map.get(data, RawPayloadContract.attachment_key()) do
      attachment when is_map(attachment) and map_size(attachment) > 0 -> {:ok, attachment}
      _attachment -> :unknown
    end
  end

  defp attachment(_data), do: :unknown

  defp external_reference(data) when is_map(data) do
    case Map.get(data, ExternalReference.external_reference_key()) ||
           Map.get(data, ExternalReference.external_reference_snake_key()) do
      external_reference when is_map(external_reference) and map_size(external_reference) > 0 ->
        {:ok, external_reference}

      _external_reference ->
        :unknown
    end
  end

  defp external_reference(_data), do: :unknown

  defp proposal_payload(proposal) when is_map(proposal) and map_size(proposal) > 0 do
    RawInput.compact(%{
      PayloadContract.provider_kind_key() => RawInput.string_value(proposal, RawPayloadContract.provider_key()),
      PayloadContract.repository_key() => RawInput.string_value(proposal, RawPayloadContract.repository_key()),
      PayloadContract.id_key() => RawInput.string_value(proposal, RawPayloadContract.id_key()),
      PayloadContract.number_key() =>
        RawInput.string_value(proposal, RawPayloadContract.number_key()) ||
          RawInput.string_value(proposal, RawPayloadContract.target_key()),
      PayloadContract.url_key() => RawInput.string_value(proposal, RawPayloadContract.url_key()),
      PayloadContract.head_ref_key() =>
        RawInput.string_value(proposal, RawPayloadContract.head_ref_name_key()) ||
          RawInput.string_value(proposal, RawPayloadContract.head_ref_key()) ||
          RawInput.string_value(proposal, RawPayloadContract.branch_key()),
      PayloadContract.head_sha_key() =>
        RawInput.string_value(proposal, RawPayloadContract.head_ref_oid_key()) ||
          RawInput.string_value(proposal, RawPayloadContract.head_sha_camel_key()) ||
          RawInput.string_value(proposal, RawPayloadContract.head_sha_key())
    })
  end

  defp proposal_payload(_proposal), do: %{}

  defp put_checks_summary(payload, checks) when is_map(checks) do
    payload
    |> Map.put(PayloadContract.checks_status_key(), CheckStatus.status(checks))
    |> Map.put(
      PayloadContract.checks_head_sha_key(),
      RawInput.string_value(checks, RawPayloadContract.head_sha_camel_key()) ||
        RawInput.string_value(checks, RawPayloadContract.head_sha_key())
    )
  end

  defp put_checks_summary(payload, _checks), do: payload

  defp put_discussion_summary(payload, discussion) when is_map(discussion) do
    actionable_count = actionable_count(discussion)

    payload
    |> Map.put(PayloadContract.discussion_status_key(), discussion_status(actionable_count))
    |> Map.put(PayloadContract.discussion_actionable_count_key(), actionable_count)
  end

  defp put_discussion_summary(payload, _discussion), do: payload

  defp actionable_count(discussion) when is_map(discussion) do
    summary = Map.get(discussion, RawPayloadContract.summary_key(), %{}) || %{}

    RawInput.integer_value(summary, RawPayloadContract.actionable_feedback_count_key()) ||
      discussion
      |> Map.get(RawPayloadContract.actionable_items_key())
      |> RawInput.list_length()
  end

  defp discussion_status(actionable_count) when actionable_count > 0, do: StatusContract.discussion_action_required_status()
  defp discussion_status(_actionable_count), do: StatusContract.discussion_clear_status()

  defp provider_kind(source_kind, source_context) do
    RawInput.string_value(source_context, RawPayloadContract.kind_key()) ||
      RawInput.string_value(source_context, RawPayloadContract.provider_key()) ||
      RawInput.string_value(source_context, RawPayloadContract.provider_kind_key()) ||
      if(source_kind, do: to_string(source_kind))
  end
end
