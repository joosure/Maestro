defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract do
  @moduledoc false

  @kind "coding_pr_delivery"
  @version 1

  @review_route_key :review
  @rework_route_key :rework
  @route_keys [:planning, :developing, @review_route_key, :merging, @rework_route_key, :resolved, :rejected]
  @configurable_route_keys [@rework_route_key]
  @default_completion_route_keys [@review_route_key, :merging, @rework_route_key, :resolved, :rejected]

  @land_execution_profile "land"
  @default_allowed_execution_profiles [@land_execution_profile]

  @requirements_option_key "requirements"
  @change_proposal_option_key "change_proposal"
  @typed_tracker_tools_option_key "typed_tracker_tools"
  @typed_repo_tools_option_key "typed_repo_tools"
  @execution_profiles_option_key "execution_profiles"
  @allowed_execution_profiles_option_key "allowed"
  @readiness_option_key "readiness"
  @review_handoff_option_key "review_handoff"
  @change_proposal_checks_option_key "change_proposal_checks"
  @mode_option_key "mode"
  @routes_option_key "routes"
  @enabled_option_key "enabled"

  @change_proposal_checks_required_when_available "required_when_available"
  @change_proposal_checks_not_required "not_required"
  @change_proposal_checks_modes [
    @change_proposal_checks_required_when_available,
    @change_proposal_checks_not_required
  ]

  @spec kind() :: String.t()
  def kind, do: @kind

  @spec version() :: pos_integer()
  def version, do: @version

  @spec review_route_key() :: atom()
  def review_route_key, do: @review_route_key

  @spec rework_route_key() :: atom()
  def rework_route_key, do: @rework_route_key

  @spec route_keys() :: [atom()]
  def route_keys, do: @route_keys

  @spec configurable_route_keys() :: [atom()]
  def configurable_route_keys, do: @configurable_route_keys

  @spec default_completion_route_keys() :: [atom()]
  def default_completion_route_keys, do: @default_completion_route_keys

  @spec land_execution_profile() :: String.t()
  def land_execution_profile, do: @land_execution_profile

  @spec default_allowed_execution_profiles() :: [String.t()]
  def default_allowed_execution_profiles, do: @default_allowed_execution_profiles

  @spec requirements_option_key() :: String.t()
  def requirements_option_key, do: @requirements_option_key

  @spec change_proposal_option_key() :: String.t()
  def change_proposal_option_key, do: @change_proposal_option_key

  @spec typed_tracker_tools_option_key() :: String.t()
  def typed_tracker_tools_option_key, do: @typed_tracker_tools_option_key

  @spec typed_repo_tools_option_key() :: String.t()
  def typed_repo_tools_option_key, do: @typed_repo_tools_option_key

  @spec execution_profiles_option_key() :: String.t()
  def execution_profiles_option_key, do: @execution_profiles_option_key

  @spec allowed_execution_profiles_option_key() :: String.t()
  def allowed_execution_profiles_option_key, do: @allowed_execution_profiles_option_key

  @spec readiness_option_key() :: String.t()
  def readiness_option_key, do: @readiness_option_key

  @spec review_handoff_option_key() :: String.t()
  def review_handoff_option_key, do: @review_handoff_option_key

  @spec change_proposal_checks_option_key() :: String.t()
  def change_proposal_checks_option_key, do: @change_proposal_checks_option_key

  @spec mode_option_key() :: String.t()
  def mode_option_key, do: @mode_option_key

  @spec routes_option_key() :: String.t()
  def routes_option_key, do: @routes_option_key

  @spec enabled_option_key() :: String.t()
  def enabled_option_key, do: @enabled_option_key

  @spec change_proposal_checks_required_when_available() :: String.t()
  def change_proposal_checks_required_when_available, do: @change_proposal_checks_required_when_available

  @spec change_proposal_checks_not_required() :: String.t()
  def change_proposal_checks_not_required, do: @change_proposal_checks_not_required

  @spec change_proposal_checks_modes() :: [String.t()]
  def change_proposal_checks_modes, do: @change_proposal_checks_modes
end
