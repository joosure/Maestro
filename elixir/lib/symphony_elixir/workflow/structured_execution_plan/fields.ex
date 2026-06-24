defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Fields do
  @moduledoc """
  Canonical JSON field keys for `workflow.execution_plan.v1`.

  Generic Agent execution-plan keys are delegated to
  `SymphonyElixir.Agent.ExecutionPlan.Fields`. Workflow-only envelope and
  scope keys are centralized here so adoption modules do not repeat field
  literals or leak workflow fields back into the generic Agent contract.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields

  @schema AgentFields.schema()
  @plan_id AgentFields.plan_id()
  @run_id AgentFields.run_id()
  @source_plan_ref AgentFields.source_plan_ref()
  @status AgentFields.status()
  @items AgentFields.items()
  @rendering AgentFields.rendering()
  @created_at AgentFields.created_at()
  @updated_at AgentFields.updated_at()
  @revision AgentFields.revision()
  @extensions AgentFields.extensions()

  @issue_id "issue_id"
  @issue_identifier "issue_identifier"
  @tracker_kind "tracker_kind"
  @workflow_profile "workflow_profile"
  @route_key "route_key"
  @lifecycle_phase "lifecycle_phase"

  @profile_kind AgentFields.kind()
  @profile_version "version"

  @workflow_required_plan_keys [
    @schema,
    @plan_id,
    @run_id,
    @issue_id,
    @tracker_kind,
    @workflow_profile,
    @route_key,
    @status,
    @items,
    @created_at,
    @updated_at,
    @revision
  ]

  @workflow_allowed_plan_keys @workflow_required_plan_keys ++
                                [
                                  @issue_identifier,
                                  @lifecycle_phase,
                                  @source_plan_ref,
                                  @rendering,
                                  @extensions
                                ]

  @workflow_required_profile_keys [@profile_kind, @profile_version]
  @workflow_allowed_profile_keys @workflow_required_profile_keys ++ [@extensions]

  @workflow_evidence_scope_keys [@run_id, @issue_id]
  @workflow_required_evidence_ref_keys AgentFields.required_evidence_ref_keys() ++ @workflow_evidence_scope_keys
  @workflow_allowed_evidence_ref_keys AgentFields.allowed_evidence_ref_keys() ++ [@issue_id]
  @workflow_envelope_identity_keys [
    @schema,
    @plan_id,
    @run_id,
    @issue_id,
    @issue_identifier,
    @tracker_kind,
    @workflow_profile,
    @route_key,
    @lifecycle_phase
  ]

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec plan_id() :: String.t()
  def plan_id, do: @plan_id

  @spec run_id() :: String.t()
  def run_id, do: @run_id

  @spec source_plan_ref() :: String.t()
  def source_plan_ref, do: @source_plan_ref

  @spec status() :: String.t()
  def status, do: @status

  @spec items() :: String.t()
  def items, do: @items

  @spec rendering() :: String.t()
  def rendering, do: @rendering

  @spec created_at() :: String.t()
  def created_at, do: @created_at

  @spec updated_at() :: String.t()
  def updated_at, do: @updated_at

  @spec revision() :: String.t()
  def revision, do: @revision

  @spec extensions() :: String.t()
  def extensions, do: @extensions

  @spec issue_id() :: String.t()
  def issue_id, do: @issue_id

  @spec issue_identifier() :: String.t()
  def issue_identifier, do: @issue_identifier

  @spec tracker_kind() :: String.t()
  def tracker_kind, do: @tracker_kind

  @spec workflow_profile() :: String.t()
  def workflow_profile, do: @workflow_profile

  @spec route_key() :: String.t()
  def route_key, do: @route_key

  @spec lifecycle_phase() :: String.t()
  def lifecycle_phase, do: @lifecycle_phase

  @spec profile_kind() :: String.t()
  def profile_kind, do: @profile_kind

  @spec profile_version() :: String.t()
  def profile_version, do: @profile_version

  @spec required_plan_keys() :: [String.t()]
  def required_plan_keys, do: @workflow_required_plan_keys

  @spec allowed_plan_keys() :: [String.t()]
  def allowed_plan_keys, do: @workflow_allowed_plan_keys

  @spec required_profile_keys() :: [String.t()]
  def required_profile_keys, do: @workflow_required_profile_keys

  @spec allowed_profile_keys() :: [String.t()]
  def allowed_profile_keys, do: @workflow_allowed_profile_keys

  @spec evidence_scope_keys() :: [String.t()]
  def evidence_scope_keys, do: @workflow_evidence_scope_keys

  @spec required_evidence_ref_keys() :: [String.t()]
  def required_evidence_ref_keys, do: @workflow_required_evidence_ref_keys

  @spec allowed_evidence_ref_keys() :: [String.t()]
  def allowed_evidence_ref_keys, do: @workflow_allowed_evidence_ref_keys

  @spec envelope_identity_keys() :: [String.t()]
  def envelope_identity_keys, do: @workflow_envelope_identity_keys
end
