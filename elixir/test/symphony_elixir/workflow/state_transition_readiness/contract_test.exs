defmodule SymphonyElixir.Workflow.StateTransitionReadinessContractModulesTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Evidence
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Result
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  test "exposes shared keys and values by responsibility" do
    assert Envelope.observations_key() == "observations"
    assert Evidence.status_key() == "status"
    assert Evidence.source_key() == "source"
    assert Evidence.observed_at_key() == "observed_at"
    assert Result.reason_codes_key() == "reason_codes"
    assert Values.passed_status() == "passed"
    assert Values.unavailable_status() == "unavailable"
    assert Values.not_required_status() == "not_required"
    assert Values.repo_provider_observed_source() == "repo_provider_observed"
  end

  test "does not expose profile-specific evidence bucket vocabulary" do
    refute function_exported?(Evidence, :workpad_key, 0)
    refute function_exported?(Evidence, :repo_key, 0)
    refute function_exported?(Evidence, :change_proposal_key, 0)
    refute function_exported?(Evidence, :linked_to_tracker_key, 0)
  end
end
