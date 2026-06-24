defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract do
  @moduledoc false

  @workflow_key "workflow"
  @profile_key "profile"
  @reconciliation_key "reconciliation"
  @config_key "change_proposal"
  @tracker_key "tracker"
  @lifecycle_key "lifecycle"
  @policy_by_route_key_key "policy_by_route_key"

  @enabled_key "enabled"
  @candidates_key "candidates"
  @gates_key "gates"
  @outcome_routes_key "outcome_routes"
  @thresholds_key "thresholds"

  @discovery_key "discovery"
  @source_routes_key "source_routes"
  @max_processed_issues_per_cycle_key "max_processed_issues_per_cycle"

  @approval_required_key "approval_required"
  @passing_checks_required_key "passing_checks_required"
  @mergeable_required_key "mergeable_required"

  @ready_key "ready"
  @changes_requested_key "changes_requested"
  @failed_checks_key "failed_checks"
  @already_merged_key "already_merged"

  @failed_checks_confirmation_count_key "failed_checks_confirmation_count"

  @source_route_scan_value "source_route_scan"
  @runtime_targeted_value "runtime_targeted"

  @config_path [@workflow_key, @reconciliation_key, @config_key]
  @config_path_name Enum.join(@config_path, ".")

  @default_enabled false
  @default_candidate_discovery :source_route_scan
  @default_require_approval true
  @default_require_passing_checks true
  @default_require_mergeable true
  @default_failed_checks_confirmation_count 2
  @default_max_processed_issues_per_cycle 25
  @max_processed_issues_per_cycle_limit 100

  @root_fields [
    @enabled_key,
    @candidates_key,
    @gates_key,
    @outcome_routes_key,
    @thresholds_key
  ]

  @candidate_fields [
    @discovery_key,
    @source_routes_key,
    @max_processed_issues_per_cycle_key
  ]

  @gate_fields [
    @approval_required_key,
    @passing_checks_required_key,
    @mergeable_required_key
  ]

  @outcome_route_fields [
    @ready_key,
    @changes_requested_key,
    @failed_checks_key,
    @already_merged_key
  ]

  @threshold_fields [
    @failed_checks_confirmation_count_key
  ]

  @candidate_discovery_mode_by_value %{
    @source_route_scan_value => :source_route_scan,
    @runtime_targeted_value => :runtime_targeted
  }

  @field_paths %{
    candidate_discovery: "#{@candidates_key}.#{@discovery_key}",
    source_routes: "#{@candidates_key}.#{@source_routes_key}",
    approval_required: "#{@gates_key}.#{@approval_required_key}",
    passing_checks_required: "#{@gates_key}.#{@passing_checks_required_key}",
    mergeable_required: "#{@gates_key}.#{@mergeable_required_key}",
    ready_outcome_route: "#{@outcome_routes_key}.#{@ready_key}",
    changes_requested_outcome_route: "#{@outcome_routes_key}.#{@changes_requested_key}",
    failed_checks_outcome_route: "#{@outcome_routes_key}.#{@failed_checks_key}",
    already_merged_outcome_route: "#{@outcome_routes_key}.#{@already_merged_key}",
    failed_checks_confirmation_count: "#{@thresholds_key}.#{@failed_checks_confirmation_count_key}",
    max_processed_issues_per_cycle: "#{@candidates_key}.#{@max_processed_issues_per_cycle_key}"
  }

  @outcome_route_specs [
    {:ready, @ready_key, @field_paths.ready_outcome_route},
    {:changes_requested, @changes_requested_key, @field_paths.changes_requested_outcome_route},
    {:failed_checks, @failed_checks_key, @field_paths.failed_checks_outcome_route},
    {:already_merged, @already_merged_key, @field_paths.already_merged_outcome_route}
  ]

  @outcome_route_requirements [
    {:ready, @field_paths.ready_outcome_route, "merging", [:dispatch]},
    {:changes_requested, @field_paths.changes_requested_outcome_route, "rework", [:dispatch]},
    {:failed_checks, @field_paths.failed_checks_outcome_route, "rework", [:dispatch]},
    {:already_merged, @field_paths.already_merged_outcome_route, "done", [:stop]}
  ]

  @spec config_key() :: String.t()
  def config_key, do: @config_key

  @spec config_path() :: [String.t()]
  def config_path, do: @config_path

  @spec config_path_name() :: String.t()
  def config_path_name, do: @config_path_name

  @spec root_fields() :: [String.t()]
  def root_fields, do: @root_fields

  @spec section_key(:candidates | :gates | :outcome_routes | :thresholds) :: String.t()
  def section_key(:candidates), do: @candidates_key
  def section_key(:gates), do: @gates_key
  def section_key(:outcome_routes), do: @outcome_routes_key
  def section_key(:thresholds), do: @thresholds_key

  @spec section_fields(:candidates | :gates | :outcome_routes | :thresholds) :: [String.t()]
  def section_fields(:candidates), do: @candidate_fields
  def section_fields(:gates), do: @gate_fields
  def section_fields(:outcome_routes), do: @outcome_route_fields
  def section_fields(:thresholds), do: @threshold_fields

  @spec field_key(atom()) :: String.t()
  def field_key(:enabled), do: @enabled_key
  def field_key(:candidate_discovery), do: @discovery_key
  def field_key(:source_routes), do: @source_routes_key
  def field_key(:max_processed_issues_per_cycle), do: @max_processed_issues_per_cycle_key
  def field_key(:approval_required), do: @approval_required_key
  def field_key(:passing_checks_required), do: @passing_checks_required_key
  def field_key(:mergeable_required), do: @mergeable_required_key
  def field_key(:failed_checks_confirmation_count), do: @failed_checks_confirmation_count_key

  @spec settings_key(:workflow | :profile | :reconciliation | :tracker | :lifecycle | :policy_by_route_key) ::
          String.t()
  def settings_key(:workflow), do: @workflow_key
  def settings_key(:profile), do: @profile_key
  def settings_key(:reconciliation), do: @reconciliation_key
  def settings_key(:tracker), do: @tracker_key
  def settings_key(:lifecycle), do: @lifecycle_key
  def settings_key(:policy_by_route_key), do: @policy_by_route_key_key

  @spec field_path(atom()) :: String.t()
  def field_path(key), do: Map.fetch!(@field_paths, key)

  @spec candidate_discovery_modes() :: [String.t()]
  def candidate_discovery_modes, do: Map.keys(@candidate_discovery_mode_by_value)

  @spec candidate_discovery_mode(String.t()) :: atom() | nil
  def candidate_discovery_mode(value) when is_binary(value),
    do: Map.get(@candidate_discovery_mode_by_value, value)

  @spec outcome_route_specs() :: [{atom(), String.t(), String.t()}]
  def outcome_route_specs, do: @outcome_route_specs

  @spec outcome_route_requirements() :: [{atom(), String.t(), String.t(), [atom()]}]
  def outcome_route_requirements, do: @outcome_route_requirements

  @spec default(atom()) :: term()
  def default(:enabled), do: @default_enabled
  def default(:candidate_discovery), do: @default_candidate_discovery
  def default(:require_approval), do: @default_require_approval
  def default(:require_passing_checks), do: @default_require_passing_checks
  def default(:require_mergeable), do: @default_require_mergeable
  def default(:failed_checks_confirmation_count), do: @default_failed_checks_confirmation_count
  def default(:max_processed_issues_per_cycle), do: @default_max_processed_issues_per_cycle

  @spec max_processed_issues_per_cycle_limit() :: pos_integer()
  def max_processed_issues_per_cycle_limit, do: @max_processed_issues_per_cycle_limit
end
