defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ContractTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceKinds
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceRecorder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  defmodule TestCapabilityProvider do
    alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.CapabilityProvider

    @behaviour CapabilityProvider

    @impl CapabilityProvider
    def issue_snapshot, do: ["test.issue_snapshot"]

    @impl CapabilityProvider
    def workpad_recorded, do: ["test.workpad_recorded"]

    @impl CapabilityProvider
    def implementation_evidence, do: ["test.implementation_evidence"]

    @impl CapabilityProvider
    def validation_passed, do: ["test.validation_passed"]

    @impl CapabilityProvider
    def change_proposal_linked, do: ["test.change_proposal_linked"]

    @impl CapabilityProvider
    def change_proposal_checks, do: ["test.change_proposal_checks"]

    @impl CapabilityProvider
    def feedback_clear, do: ["test.feedback_clear"]

    @impl CapabilityProvider
    def unknown, do: []
  end

  defmodule IncompleteCapabilityProvider do
    def workpad_recorded, do: ["test.workpad_recorded"]
  end

  test "readiness facade exposes contribution modules" do
    assert Readiness.policies() == [ReviewHandoff]
    assert Readiness.evidence_recorders() == [EvidenceRecorder]
    assert is_map(Readiness.retry_policies())
  end

  test "coding PR delivery policy id is derived from the profile kind" do
    assert Contract.coding_pr_delivery_policy_id() ==
             CodingPrDelivery.kind() <> "." <> Contract.schema()
  end

  test "exposes review handoff readiness requirements" do
    assert Contract.not_ready_error() == "review_handoff_not_ready"

    assert Contract.passing_change_proposal_statuses() == [
             Values.linked_status(),
             Values.created_status(),
             Values.updated_status()
           ]

    assert Contract.passing_check_statuses() == [
             Values.passed_status(),
             Values.not_required_status()
           ]

    assert Contract.passing_feedback_statuses() == [
             Values.clear_status(),
             Values.not_required_status()
           ]
  end

  test "exposes review handoff machine-readable check identifiers" do
    assert Contract.check_key(:workpad_recorded) == "workpad_recorded"
    assert Contract.reason_code(:workpad_record_stale) == "workpad_record_stale"
    assert Contract.reason_code(:validation_head_stale) == "validation_head_stale"
    assert Contract.observed_evidence_code(:checks_ready) == "checks.ready"
  end

  test "structured plan evidence kinds are extension-owned contract values" do
    assert EvidenceKinds.change_proposal_kinds() == [
             "repo_create_or_update_change_proposal",
             "repo_change_proposal_snapshot"
           ]

    assert EvidenceKinds.tracker_linkage_kinds() == ["tracker_attach_change_proposal"]
    assert EvidenceKinds.handoff_record_kinds() == ["tracker_upsert_workpad"]
  end

  test "evidence recorder emits bounded diagnostics for invalid options" do
    log =
      capture_log(fn ->
        assert :ok =
                 EvidenceRecorder.record_typed_tool_result(
                   :tracker,
                   %{},
                   "linear_upsert_workpad",
                   %{},
                   {:success, %{}},
                   [:secret_invalid_opts]
                 )
      end)

    assert log =~ "coding_pr_delivery_review_handoff_evidence_recorder_invalid_options"
    assert log =~ "value_type"
    assert log =~ "list"
    refute log =~ "secret_invalid_opts"
  end

  test "remediation capability provider is injectable" do
    assert [
             %{
               "reason_code" => "workpad_record_missing",
               "check" => "workpad_recorded",
               "capabilities" => ["test.workpad_recorded"]
             }
           ] =
             Remediation.actions(
               [
                 %{
                   "reason_code" => "workpad_record_missing",
                   "key" => "workpad_recorded"
                 }
               ],
               capability_provider: TestCapabilityProvider
             )
  end

  test "remediation ignores incomplete capability providers" do
    assert [%{"capabilities" => capabilities}] =
             Remediation.actions(
               [
                 %{
                   "reason_code" => "workpad_record_missing",
                   "key" => "workpad_recorded"
                 }
               ],
               capability_provider: IncompleteCapabilityProvider
             )

    refute capabilities == ["test.workpad_recorded"]
    assert is_list(capabilities)
  end
end
