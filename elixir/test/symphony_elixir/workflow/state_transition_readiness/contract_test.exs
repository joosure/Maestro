defmodule SymphonyElixir.Workflow.StateTransitionReadiness.ContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Evidence
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Result
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  test "exposes shared evidence keys and values" do
    assert Contract.observations_key() == "observations"
    assert Contract.workpad_key() == "workpad"
    assert Contract.change_proposal_key() == "change_proposal"
    assert Contract.status_key() == "status"
    assert Contract.passed_status() == "passed"
    assert Contract.not_required_status() == "not_required"
  end

  test "keeps narrower contract modules available by responsibility" do
    assert Envelope.observations_key() == Contract.observations_key()
    assert Evidence.change_proposal_key() == Contract.change_proposal_key()
    assert Result.reason_codes_key() == Contract.reason_codes_key()
    assert Values.repo_provider_observed_source() == Contract.repo_provider_observed_source()
  end
end
