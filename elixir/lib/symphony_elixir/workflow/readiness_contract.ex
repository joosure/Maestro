defmodule SymphonyElixir.Workflow.ReadinessContract do
  @moduledoc """
  Shared string contract for workflow readiness and completion-validation payloads.
  """

  @key_key "key"
  @status_key "status"
  @profile_key "profile"
  @route_key "route"
  @required_outputs_key "required_outputs"
  @allowed_completion_routes_key "allowed_completion_routes"
  @evidence_requirements_key "evidence_requirements"
  @handoff_expectations_key "handoff_expectations"
  @checks_key "checks"
  @missing_evidence_key "missing_evidence"
  @required_evidence_key "required_evidence"
  @observed_evidence_key "observed_evidence"
  @gate_key "gate"
  @category_key "category"
  @reason_key "reason"

  @passed "passed"
  @failed "failed"
  @skipped "skipped"
  @blocked "blocked"
  @waiting "waiting"
  @open "open"

  @capability_gate "capability"
  @approval_gate "approval"
  @human_review_gate "human_review"
  @route_wait_gate "route_wait"
  @terminal_gate "terminal"
  @route_preparation_gate "route_preparation"
  @unknown_route_action_gate "unknown_route_action"
  @route_gate "route"
  @merge_gate "merge"
  @dispatch_gate "dispatch"

  @spec key_key() :: String.t()
  def key_key, do: @key_key

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec profile_key() :: String.t()
  def profile_key, do: @profile_key

  @spec route_key() :: String.t()
  def route_key, do: @route_key

  @spec required_outputs_key() :: String.t()
  def required_outputs_key, do: @required_outputs_key

  @spec allowed_completion_routes_key() :: String.t()
  def allowed_completion_routes_key, do: @allowed_completion_routes_key

  @spec evidence_requirements_key() :: String.t()
  def evidence_requirements_key, do: @evidence_requirements_key

  @spec handoff_expectations_key() :: String.t()
  def handoff_expectations_key, do: @handoff_expectations_key

  @spec checks_key() :: String.t()
  def checks_key, do: @checks_key

  @spec missing_evidence_key() :: String.t()
  def missing_evidence_key, do: @missing_evidence_key

  @spec required_evidence_key() :: String.t()
  def required_evidence_key, do: @required_evidence_key

  @spec observed_evidence_key() :: String.t()
  def observed_evidence_key, do: @observed_evidence_key

  @spec gate_key() :: String.t()
  def gate_key, do: @gate_key

  @spec category_key() :: String.t()
  def category_key, do: @category_key

  @spec reason_key() :: String.t()
  def reason_key, do: @reason_key

  @spec passed() :: String.t()
  def passed, do: @passed

  @spec failed() :: String.t()
  def failed, do: @failed

  @spec skipped() :: String.t()
  def skipped, do: @skipped

  @spec blocked() :: String.t()
  def blocked, do: @blocked

  @spec waiting() :: String.t()
  def waiting, do: @waiting

  @spec open() :: String.t()
  def open, do: @open

  @spec capability_gate() :: String.t()
  def capability_gate, do: @capability_gate

  @spec approval_gate() :: String.t()
  def approval_gate, do: @approval_gate

  @spec human_review_gate() :: String.t()
  def human_review_gate, do: @human_review_gate

  @spec route_wait_gate() :: String.t()
  def route_wait_gate, do: @route_wait_gate

  @spec terminal_gate() :: String.t()
  def terminal_gate, do: @terminal_gate

  @spec route_preparation_gate() :: String.t()
  def route_preparation_gate, do: @route_preparation_gate

  @spec unknown_route_action_gate() :: String.t()
  def unknown_route_action_gate, do: @unknown_route_action_gate

  @spec route_gate() :: String.t()
  def route_gate, do: @route_gate

  @spec merge_gate() :: String.t()
  def merge_gate, do: @merge_gate

  @spec dispatch_gate() :: String.t()
  def dispatch_gate, do: @dispatch_gate

  @spec status(term()) :: term()
  def status(payload) when is_map(payload), do: Map.get(payload, @status_key)
  def status(_payload), do: nil

  @spec gate(term()) :: term()
  def gate(payload) when is_map(payload), do: Map.get(payload, @gate_key)
  def gate(_payload), do: nil

  @spec passed?(term()) :: boolean()
  def passed?(payload) when is_map(payload), do: status(payload) == @passed
  def passed?(_payload), do: false
end
