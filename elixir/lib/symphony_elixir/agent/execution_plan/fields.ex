defmodule SymphonyElixir.Agent.ExecutionPlan.Fields do
  @moduledoc """
  Canonical JSON field keys for `agent.execution_plan.v1`.

  These strings are the external schema contract. Runtime modules should read
  them through this boundary instead of repeating field literals.
  """

  @schema "schema"
  @plan_id "plan_id"
  @context "context"
  @status "status"
  @items "items"
  @source_plan_ref "source_plan_ref"
  @rendering "rendering"
  @extensions "extensions"
  @created_at "created_at"
  @updated_at "updated_at"
  @revision "revision"
  @artifact_id "artifact_id"
  @hash "hash"

  @context_kind "context_kind"
  @tenant_id "tenant_id"
  @workspace_id "workspace_id"
  @run_id "run_id"
  @agent_session_id "agent_session_id"
  @task_id "task_id"
  @recipe_run_id "recipe_run_id"
  @workflow_ref "workflow_ref"
  @repo_ref "repo_ref"
  @tracker_ref "tracker_ref"
  @policy_refs "policy_refs"
  @source "source"
  @mode "mode"

  @item_id "item_id"
  @parent_item_id "parent_item_id"
  @title "title"
  @kind "kind"
  @required "required"
  @criticality "criticality"
  @owned_by "owned_by"
  @depends_on "depends_on"
  @evidence_requirements "evidence_requirements"
  @evidence_refs "evidence_refs"
  @status_reason "status_reason"

  @evidence_kind "evidence_kind"
  @required_fields "required_fields"
  @trust_classes "trust_classes"
  @matcher "matcher"

  @evidence_id "evidence_id"
  @producer "producer"
  @observed_at "observed_at"
  @payload "payload"
  @evidence_context_key "context_key"
  @reason_code "reason_code"
  @actor "actor"
  @message "message"

  @profile_kind "profile_kind"
  @profile_version "profile_version"
  @route_key "route_key"
  @lifecycle_phase "lifecycle_phase"
  @issue_id "issue_id"
  @issue_identifier "issue_identifier"
  @tracker_kind "tracker_kind"
  @provider "provider"
  @repository_id "repository_id"
  @branch "branch"

  @required_plan_keys [@schema, @plan_id, @context, @status, @items, @created_at, @updated_at, @revision]
  @allowed_plan_keys @required_plan_keys ++ [@source_plan_ref, @rendering, @extensions]
  @required_source_plan_ref_keys [@artifact_id, @hash]
  @allowed_source_plan_ref_keys @required_source_plan_ref_keys ++ [@extensions]

  @required_context_keys [@context_kind, @workspace_id, @run_id, @source, @mode]

  @allowed_context_keys @required_context_keys ++
                          [
                            @tenant_id,
                            @agent_session_id,
                            @task_id,
                            @recipe_run_id,
                            @workflow_ref,
                            @repo_ref,
                            @tracker_ref,
                            @policy_refs,
                            @extensions
                          ]

  @required_item_keys [
    @item_id,
    @title,
    @kind,
    @status,
    @required,
    @criticality,
    @owned_by,
    @source,
    @depends_on,
    @evidence_requirements,
    @evidence_refs,
    @created_at,
    @updated_at,
    @revision
  ]

  @allowed_item_keys @required_item_keys ++ [@parent_item_id, @status_reason, @extensions]
  @required_status_reason_keys [@reason_code]
  @allowed_status_reason_keys @required_status_reason_keys ++ [@actor, @evidence_id, @message, @extensions]

  @required_evidence_requirement_keys [@evidence_kind, @required_fields, @trust_classes]
  @allowed_evidence_requirement_keys @required_evidence_requirement_keys ++ [@required, @matcher, @extensions]

  @required_evidence_ref_keys [@evidence_id, @evidence_kind, @source, @producer, @observed_at, @payload]
  @allowed_evidence_ref_keys @required_evidence_ref_keys ++ [@evidence_context_key, @run_id, @task_id, @extensions]

  @allowed_workflow_ref_keys [
    @profile_kind,
    @profile_version,
    @route_key,
    @lifecycle_phase,
    @issue_id,
    @issue_identifier,
    @tracker_kind
  ]
  @allowed_repo_ref_keys [@provider, @repository_id, @branch]
  @allowed_tracker_ref_keys [@tracker_kind, @issue_id, @issue_identifier]

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec plan_id() :: String.t()
  def plan_id, do: @plan_id

  @spec context() :: String.t()
  def context, do: @context

  @spec status() :: String.t()
  def status, do: @status

  @spec items() :: String.t()
  def items, do: @items

  @spec source_plan_ref() :: String.t()
  def source_plan_ref, do: @source_plan_ref

  @spec rendering() :: String.t()
  def rendering, do: @rendering

  @spec extensions() :: String.t()
  def extensions, do: @extensions

  @spec created_at() :: String.t()
  def created_at, do: @created_at

  @spec updated_at() :: String.t()
  def updated_at, do: @updated_at

  @spec revision() :: String.t()
  def revision, do: @revision

  @spec artifact_id() :: String.t()
  def artifact_id, do: @artifact_id

  @spec hash() :: String.t()
  def hash, do: @hash

  @spec context_kind() :: String.t()
  def context_kind, do: @context_kind

  @spec tenant_id() :: String.t()
  def tenant_id, do: @tenant_id

  @spec workspace_id() :: String.t()
  def workspace_id, do: @workspace_id

  @spec run_id() :: String.t()
  def run_id, do: @run_id

  @spec agent_session_id() :: String.t()
  def agent_session_id, do: @agent_session_id

  @spec task_id() :: String.t()
  def task_id, do: @task_id

  @spec recipe_run_id() :: String.t()
  def recipe_run_id, do: @recipe_run_id

  @spec workflow_ref() :: String.t()
  def workflow_ref, do: @workflow_ref

  @spec repo_ref() :: String.t()
  def repo_ref, do: @repo_ref

  @spec tracker_ref() :: String.t()
  def tracker_ref, do: @tracker_ref

  @spec policy_refs() :: String.t()
  def policy_refs, do: @policy_refs

  @spec source() :: String.t()
  def source, do: @source

  @spec mode() :: String.t()
  def mode, do: @mode

  @spec item_id() :: String.t()
  def item_id, do: @item_id

  @spec parent_item_id() :: String.t()
  def parent_item_id, do: @parent_item_id

  @spec title() :: String.t()
  def title, do: @title

  @spec kind() :: String.t()
  def kind, do: @kind

  @spec required() :: String.t()
  def required, do: @required

  @spec criticality() :: String.t()
  def criticality, do: @criticality

  @spec owned_by() :: String.t()
  def owned_by, do: @owned_by

  @spec depends_on() :: String.t()
  def depends_on, do: @depends_on

  @spec evidence_requirements() :: String.t()
  def evidence_requirements, do: @evidence_requirements

  @spec evidence_refs() :: String.t()
  def evidence_refs, do: @evidence_refs

  @spec status_reason() :: String.t()
  def status_reason, do: @status_reason

  @spec evidence_kind() :: String.t()
  def evidence_kind, do: @evidence_kind

  @spec required_fields() :: String.t()
  def required_fields, do: @required_fields

  @spec trust_classes() :: String.t()
  def trust_classes, do: @trust_classes

  @spec matcher() :: String.t()
  def matcher, do: @matcher

  @spec evidence_id() :: String.t()
  def evidence_id, do: @evidence_id

  @spec producer() :: String.t()
  def producer, do: @producer

  @spec observed_at() :: String.t()
  def observed_at, do: @observed_at

  @spec payload() :: String.t()
  def payload, do: @payload

  @spec evidence_context_key() :: String.t()
  def evidence_context_key, do: @evidence_context_key

  @spec reason_code() :: String.t()
  def reason_code, do: @reason_code

  @spec actor() :: String.t()
  def actor, do: @actor

  @spec message() :: String.t()
  def message, do: @message

  @spec profile_kind() :: String.t()
  def profile_kind, do: @profile_kind

  @spec profile_version() :: String.t()
  def profile_version, do: @profile_version

  @spec route_key() :: String.t()
  def route_key, do: @route_key

  @spec lifecycle_phase() :: String.t()
  def lifecycle_phase, do: @lifecycle_phase

  @spec issue_id() :: String.t()
  def issue_id, do: @issue_id

  @spec issue_identifier() :: String.t()
  def issue_identifier, do: @issue_identifier

  @spec tracker_kind() :: String.t()
  def tracker_kind, do: @tracker_kind

  @spec provider() :: String.t()
  def provider, do: @provider

  @spec repository_id() :: String.t()
  def repository_id, do: @repository_id

  @spec branch() :: String.t()
  def branch, do: @branch

  @spec required_plan_keys() :: [String.t()]
  def required_plan_keys, do: @required_plan_keys

  @spec allowed_plan_keys() :: [String.t()]
  def allowed_plan_keys, do: @allowed_plan_keys

  @spec required_source_plan_ref_keys() :: [String.t()]
  def required_source_plan_ref_keys, do: @required_source_plan_ref_keys

  @spec allowed_source_plan_ref_keys() :: [String.t()]
  def allowed_source_plan_ref_keys, do: @allowed_source_plan_ref_keys

  @spec required_context_keys() :: [String.t()]
  def required_context_keys, do: @required_context_keys

  @spec allowed_context_keys() :: [String.t()]
  def allowed_context_keys, do: @allowed_context_keys

  @spec required_item_keys() :: [String.t()]
  def required_item_keys, do: @required_item_keys

  @spec allowed_item_keys() :: [String.t()]
  def allowed_item_keys, do: @allowed_item_keys

  @spec required_status_reason_keys() :: [String.t()]
  def required_status_reason_keys, do: @required_status_reason_keys

  @spec allowed_status_reason_keys() :: [String.t()]
  def allowed_status_reason_keys, do: @allowed_status_reason_keys

  @spec required_evidence_requirement_keys() :: [String.t()]
  def required_evidence_requirement_keys, do: @required_evidence_requirement_keys

  @spec allowed_evidence_requirement_keys() :: [String.t()]
  def allowed_evidence_requirement_keys, do: @allowed_evidence_requirement_keys

  @spec required_evidence_ref_keys() :: [String.t()]
  def required_evidence_ref_keys, do: @required_evidence_ref_keys

  @spec allowed_evidence_ref_keys() :: [String.t()]
  def allowed_evidence_ref_keys, do: @allowed_evidence_ref_keys

  @spec allowed_workflow_ref_keys() :: [String.t()]
  def allowed_workflow_ref_keys, do: @allowed_workflow_ref_keys

  @spec allowed_repo_ref_keys() :: [String.t()]
  def allowed_repo_ref_keys, do: @allowed_repo_ref_keys

  @spec allowed_tracker_ref_keys() :: [String.t()]
  def allowed_tracker_ref_keys, do: @allowed_tracker_ref_keys
end
