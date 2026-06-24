defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Checks do
  @moduledoc """
  Check predicates for Coding PR Delivery completion validation.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceReader
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Values
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @spec change_proposal_exists?(map()) :: boolean()
  def change_proposal_exists?(evidence) do
    change_proposal =
      EvidenceReader.first_map([
        EvidenceReader.field(evidence, Evidence.change_proposal_key()),
        EvidenceReader.field(evidence, Evidence.change_proposal_camel_key()),
        evidence |> EvidenceReader.field(Evidence.data_key()) |> EvidenceReader.field(Evidence.change_proposal_camel_key()),
        evidence |> EvidenceReader.field(Evidence.data_key()) |> EvidenceReader.field(Evidence.change_proposal_key()),
        EvidenceReader.field(evidence, Evidence.pr_key()),
        EvidenceReader.field(evidence, Evidence.pull_request_key())
      ])

    EvidenceReader.truthy?(EvidenceReader.field(change_proposal, Evidence.exists_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(change_proposal, Evidence.url_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(change_proposal, Evidence.number_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(change_proposal, Evidence.target_key()))
  end

  @spec change_proposal_linked_to_tracker?(map()) :: boolean()
  def change_proposal_linked_to_tracker?(evidence) do
    attachment =
      EvidenceReader.first_map([
        EvidenceReader.field(evidence, Evidence.attachment_key()),
        evidence |> EvidenceReader.field(Evidence.data_key()) |> EvidenceReader.field(Evidence.attachment_key()),
        evidence |> EvidenceReader.field(Evidence.tracker_key()) |> EvidenceReader.field(Evidence.attachment_key())
      ])

    EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.tracker_key(), Evidence.change_proposal_attached_key()])) or
      EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.tracker_key(), Evidence.tracker_attached_key()])) or
      EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.change_proposal_key(), Evidence.linked_issue_key()])) or
      EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.change_proposal_camel_key(), Evidence.linked_issue_camel_key()])) or
      EvidenceReader.truthy?(EvidenceReader.deep_field(evidence, [Evidence.change_proposal_key(), Evidence.tracker_linked_key()])) or
      EvidenceReader.present_string?(EvidenceReader.field(attachment, Evidence.url_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(attachment, Evidence.id_key()))
  end

  @spec commit_or_diff_exists?(map()) :: boolean()
  def commit_or_diff_exists?(evidence) do
    repo = EvidenceReader.field(evidence, Evidence.repo_key())
    commits = EvidenceReader.field(repo, Evidence.commits_key()) || EvidenceReader.field(evidence, Evidence.commits_key())
    diff = EvidenceReader.field(repo, Evidence.diff_key()) || EvidenceReader.field(evidence, Evidence.diff_key())

    EvidenceReader.truthy?(EvidenceReader.field(repo, Evidence.commit_exists_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(repo, Evidence.diff_exists_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(repo, Evidence.diff_present_key())) or
      EvidenceReader.non_empty_list?(commits) or
      EvidenceReader.present_string?(EvidenceReader.field(repo, Evidence.head_sha_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(diff, Evidence.summary_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(diff, Evidence.present_key()))
  end

  @spec checks_read_and_recorded?(map()) :: boolean()
  def checks_read_and_recorded?(evidence) do
    checks = checks_map(evidence)

    (EvidenceReader.truthy?(EvidenceReader.field(checks, Evidence.read_key())) and checks_result_recorded?(checks)) or
      EvidenceReader.non_empty_list?(EvidenceReader.field(checks, Evidence.items_key())) or
      EvidenceReader.non_empty_list?(EvidenceReader.field(checks, Evidence.checks_key()))
  end

  @spec checks_passing?(map()) :: boolean()
  def checks_passing?(evidence) do
    checks = checks_map(evidence)

    EvidenceReader.field(checks, Evidence.status_key()) in Values.passing_check_statuses() or
      EvidenceReader.field(checks, Evidence.summary_key()) in Values.passing_check_statuses() or
      EvidenceReader.field(checks, Evidence.check_summary_key()) in Values.passing_check_statuses() or
      EvidenceReader.truthy?(EvidenceReader.field(checks, Evidence.passing_key()))
  end

  @spec tracker_workpad_written?(map()) :: boolean()
  def tracker_workpad_written?(evidence) do
    tracker = EvidenceReader.field(evidence, Evidence.tracker_key())

    EvidenceReader.truthy?(EvidenceReader.field(tracker, Evidence.workpad_written_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(tracker, Evidence.comment_written_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(tracker, Evidence.workpad_upserted_key())) or
      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.data_key(), Evidence.comment_key(), Evidence.id_key()])) or
      EvidenceReader.present_string?(EvidenceReader.deep_field(evidence, [Evidence.tracker_key(), Evidence.comment_key(), Evidence.id_key()]))
  end

  @spec change_proposal_approved?(map()) :: boolean()
  def change_proposal_approved?(evidence) do
    review =
      EvidenceReader.first_map([
        EvidenceReader.field(evidence, Evidence.review_key()),
        EvidenceReader.field(evidence, Evidence.reviews_key()),
        evidence |> EvidenceReader.field(Evidence.change_proposal_key()) |> EvidenceReader.field(Evidence.review_key()),
        evidence |> EvidenceReader.field(Evidence.change_proposal_camel_key()) |> EvidenceReader.field(Evidence.review_key())
      ])

    EvidenceReader.field(review, Evidence.status_key()) in Values.approved_review_statuses() or
      EvidenceReader.field(review, Evidence.summary_key()) in Values.approved_review_statuses() or
      EvidenceReader.field(review, Evidence.review_summary_key()) in Values.approved_review_statuses() or
      EvidenceReader.truthy?(EvidenceReader.field(review, Evidence.approved_key()))
  end

  @spec merge_capability_available?(map()) :: boolean()
  def merge_capability_available?(capabilities) when is_map(capabilities) do
    if EvidenceReader.field(capabilities, Evidence.checked_key()) == false do
      false
    else
      merge_capability_available_from_sets?(capabilities)
    end
  end

  @spec tracker_merge_state_observed?(map()) :: boolean()
  def tracker_merge_state_observed?(evidence) do
    route = EvidenceReader.field(evidence, Evidence.route_key())
    tracker = EvidenceReader.field(evidence, Evidence.tracker_key())

    EvidenceReader.route_value(route, Evidence.key_key()) == Values.merge_route_key() or
      EvidenceReader.route_value(route, Evidence.current_key()) == Values.merge_route_key() or
      EvidenceReader.route_value(route, Evidence.target_key()) == Values.merge_route_key() or
      tracker_merge_phase?(tracker) or
      EvidenceReader.truthy?(EvidenceReader.field(tracker, Evidence.merge_approved_key()))
  end

  @spec route_allowed?(term(), term()) :: boolean()
  def route_allowed?(route_key, allowed_routes)
      when is_binary(route_key) and is_list(allowed_routes),
      do: route_key in allowed_routes

  def route_allowed?(_route_key, _allowed_routes), do: false

  defp checks_result_recorded?(checks) when is_map(checks) do
    EvidenceReader.present_string?(EvidenceReader.field(checks, Evidence.status_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(checks, Evidence.summary_key())) or
      EvidenceReader.present_string?(EvidenceReader.field(checks, Evidence.check_summary_key())) or
      EvidenceReader.truthy?(EvidenceReader.field(checks, Evidence.recorded_key()))
  end

  defp checks_map(evidence) do
    EvidenceReader.first_map([
      EvidenceReader.field(evidence, Evidence.checks_key()),
      evidence |> EvidenceReader.field(Evidence.data_key()) |> EvidenceReader.field(Evidence.checks_key()),
      EvidenceReader.field(evidence, Evidence.ci_key()),
      evidence |> EvidenceReader.field(Evidence.change_proposal_key()) |> EvidenceReader.field(Evidence.checks_key()),
      evidence |> EvidenceReader.field(Evidence.change_proposal_camel_key()) |> EvidenceReader.field(Evidence.checks_key())
    ])
  end

  defp merge_capability_available_from_sets?(capabilities) do
    available =
      capabilities
      |> EvidenceReader.field(Evidence.available_key())
      |> EvidenceReader.capability_set()

    missing =
      capabilities
      |> EvidenceReader.field(Evidence.missing_key())
      |> EvidenceReader.capability_set()

    merge_capabilities = Values.merge_capabilities()

    Enum.any?(merge_capabilities, &MapSet.member?(available, &1)) and
      Enum.all?(merge_capabilities, &(not MapSet.member?(missing, &1)))
  end

  defp tracker_merge_phase?(tracker) do
    phase = EvidenceReader.field(tracker, Evidence.lifecycle_phase_key()) || EvidenceReader.field(tracker, Evidence.state_key())
    WorkflowLifecycle.merge_phase?(phase)
  end
end
