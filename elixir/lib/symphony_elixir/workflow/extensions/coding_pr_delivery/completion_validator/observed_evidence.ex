defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.ObservedEvidence do
  @moduledoc """
  Builds observed-evidence labels for Coding PR Delivery completion checks.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Checks
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceReader

  @spec change_proposal(map()) :: [String.t()]
  def change_proposal(evidence) do
    cond do
      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.change_proposal_key(), Evidence.url_key()])) ->
        [Evidence.change_proposal_url_label()]

      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.change_proposal_camel_key(), Evidence.url_key()])) ->
        [Evidence.change_proposal_camel_url_label()]

      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.data_key(), Evidence.change_proposal_camel_key(), Evidence.url_key()])) ->
        [Evidence.data_change_proposal_camel_url_label()]

      Checks.change_proposal_exists?(evidence) ->
        [Evidence.change_proposal_label()]

      true ->
        []
    end
  end

  @spec tracker_link(map()) :: [String.t()]
  def tracker_link(evidence) do
    cond do
      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.data_key(), Evidence.attachment_key(), Evidence.id_key()])) ->
        [Evidence.data_attachment_id_label()]

      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.attachment_key(), Evidence.id_key()])) ->
        [Evidence.attachment_id_label()]

      Checks.change_proposal_linked_to_tracker?(evidence) ->
        [Evidence.tracker_change_proposal_attached_label()]

      true ->
        []
    end
  end

  @spec repo_change(map()) :: [String.t()]
  def repo_change(evidence) do
    cond do
      EvidenceReader.non_empty_list?(EvidenceReader.deep_field(evidence, [Evidence.repo_key(), Evidence.commits_key()])) ->
        [Evidence.repo_commits_label()]

      EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.repo_key(), Evidence.diff_present_key()])) ->
        [Evidence.repo_diff_present_label()]

      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.repo_key(), Evidence.head_sha_key()])) ->
        [Evidence.repo_head_sha_label()]

      true ->
        []
    end
  end

  @spec checks(map()) :: [String.t()]
  def checks(evidence) do
    cond do
      Checks.checks_passing?(evidence) -> [Evidence.checks_passing_label()]
      Checks.checks_read_and_recorded?(evidence) -> [Evidence.checks_read_label()]
      true -> []
    end
  end

  @spec tracker_write(map()) :: [String.t()]
  def tracker_write(evidence) do
    if Checks.tracker_workpad_written?(evidence), do: [Evidence.tracker_workpad_written_label()], else: []
  end

  @spec route(term()) :: [String.t()]
  def route(route_key) when is_binary(route_key), do: [Evidence.route_label(route_key)]
  def route(_route_key), do: []

  @spec approval(map()) :: [String.t()]
  def approval(evidence) do
    if Checks.change_proposal_approved?(evidence), do: [Evidence.review_approved_label()], else: []
  end

  @spec merge_capability(map()) :: [String.t()]
  def merge_capability(capabilities) do
    if Checks.merge_capability_available?(capabilities), do: [Evidence.merge_capability_available_label()], else: []
  end

  @spec tracker_merge_state(map()) :: [String.t()]
  def tracker_merge_state(evidence) do
    if Checks.tracker_merge_state_observed?(evidence), do: [Evidence.tracker_merge_state_label()], else: []
  end
end
