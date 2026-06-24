defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Contract do
  @moduledoc """
  Machine-readable check and required-evidence contract for Coding PR Delivery
  completion validation.
  """

  @change_proposal_exists_check "change_proposal_exists"
  @change_proposal_linked_to_tracker_check "change_proposal_linked_to_tracker"
  @commit_or_diff_exists_check "commit_or_diff_exists"
  @checks_read_and_recorded_check "checks_read_and_recorded"
  @tracker_workpad_written_check "tracker_workpad_written"
  @completion_route_allowed_check "completion_route_allowed"
  @change_proposal_approved_check "change_proposal_approved"
  @checks_passing_check "checks_passing"
  @merge_capability_available_check "merge_capability_available"
  @tracker_merge_state_observed_check "tracker_merge_state_observed"
  @completion_validator_options_valid_check "completion_validator_options_valid"
  @completion_validator_input_valid_check "completion_validator_input_valid"

  @linked_change_proposal_required "linked change proposal exists"
  @tracker_link_required "change proposal is attached or linked to the tracker issue"
  @commit_or_diff_required "commit or diff evidence exists"
  @checks_read_required "CI/check evidence was read and recorded"
  @tracker_write_required "tracker workpad/comment was written"
  @completion_route_required "current or target route is allowed by the completion contract"
  @human_approval_required "required human approval is present"
  @checks_passing_required "required CI/checks passed"
  @merge_capability_required "merge capability is available"
  @tracker_merge_state_required "tracker state or approval evidence indicates merge is authorized"
  @valid_completion_validator_options_required "completion validator options are valid"
  @valid_completion_validator_input_required "completion validator input is valid"

  @spec change_proposal_exists_check() :: String.t()
  def change_proposal_exists_check, do: @change_proposal_exists_check

  @spec change_proposal_linked_to_tracker_check() :: String.t()
  def change_proposal_linked_to_tracker_check, do: @change_proposal_linked_to_tracker_check

  @spec commit_or_diff_exists_check() :: String.t()
  def commit_or_diff_exists_check, do: @commit_or_diff_exists_check

  @spec checks_read_and_recorded_check() :: String.t()
  def checks_read_and_recorded_check, do: @checks_read_and_recorded_check

  @spec tracker_workpad_written_check() :: String.t()
  def tracker_workpad_written_check, do: @tracker_workpad_written_check

  @spec completion_route_allowed_check() :: String.t()
  def completion_route_allowed_check, do: @completion_route_allowed_check

  @spec change_proposal_approved_check() :: String.t()
  def change_proposal_approved_check, do: @change_proposal_approved_check

  @spec checks_passing_check() :: String.t()
  def checks_passing_check, do: @checks_passing_check

  @spec merge_capability_available_check() :: String.t()
  def merge_capability_available_check, do: @merge_capability_available_check

  @spec tracker_merge_state_observed_check() :: String.t()
  def tracker_merge_state_observed_check, do: @tracker_merge_state_observed_check

  @spec completion_validator_options_valid_check() :: String.t()
  def completion_validator_options_valid_check, do: @completion_validator_options_valid_check

  @spec completion_validator_input_valid_check() :: String.t()
  def completion_validator_input_valid_check, do: @completion_validator_input_valid_check

  @spec linked_change_proposal_required() :: String.t()
  def linked_change_proposal_required, do: @linked_change_proposal_required

  @spec tracker_link_required() :: String.t()
  def tracker_link_required, do: @tracker_link_required

  @spec commit_or_diff_required() :: String.t()
  def commit_or_diff_required, do: @commit_or_diff_required

  @spec checks_read_required() :: String.t()
  def checks_read_required, do: @checks_read_required

  @spec tracker_write_required() :: String.t()
  def tracker_write_required, do: @tracker_write_required

  @spec completion_route_required() :: String.t()
  def completion_route_required, do: @completion_route_required

  @spec human_approval_required() :: String.t()
  def human_approval_required, do: @human_approval_required

  @spec checks_passing_required() :: String.t()
  def checks_passing_required, do: @checks_passing_required

  @spec merge_capability_required() :: String.t()
  def merge_capability_required, do: @merge_capability_required

  @spec tracker_merge_state_required() :: String.t()
  def tracker_merge_state_required, do: @tracker_merge_state_required

  @spec valid_completion_validator_options_required() :: String.t()
  def valid_completion_validator_options_required, do: @valid_completion_validator_options_required

  @spec valid_completion_validator_input_required() :: String.t()
  def valid_completion_validator_input_required, do: @valid_completion_validator_input_required
end
