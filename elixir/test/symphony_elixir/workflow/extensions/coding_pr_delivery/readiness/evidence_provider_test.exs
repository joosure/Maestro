defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProviderTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceProvider.Projector
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Facts

  test "readiness facade owns evidence provider contribution" do
    assert Readiness.evidence_providers() == [EvidenceProvider]
    assert CodingPrDelivery.readiness_evidence_providers() == [EvidenceProvider]
  end

  test "projector keeps readiness evidence shape stable" do
    facts = %Facts{
      repository: "owner/repo",
      number: 123,
      url: "https://example.test/pulls/123",
      branch: "feature/example",
      head_sha: "abc123",
      provider_state: Contract.provider_state_open(),
      review_summary: Contract.review_summary_approved(),
      check_summary: Contract.check_summary_passing(),
      mergeability_summary: Contract.mergeability_summary_mergeable(),
      unresolved_actionable_feedback?: false
    }

    issue = %Issue{id: "ISSUE-1", state: "ready_for_merge"}

    assert %{
             change_proposal: %{
               url: "https://example.test/pulls/123",
               number: 123,
               target: 123,
               branch: "feature/example",
               provider_state: "open",
               linked_issue: true,
               tracker_linked: true
             },
             repo: %{
               repository: "owner/repo",
               branch: "feature/example",
               head_sha: "abc123",
               diff_present: true
             },
             checks: %{
               read: true,
               status: "passing",
               check_summary: "passing",
               passing: true
             },
             review: %{
               approved: true,
               status: "approved",
               review_summary: "approved"
             },
             tracker: %{
               state: "ready_for_merge",
               change_proposal_attached: true,
               merge_approved: true
             }
           } == Projector.evidence(facts, issue)
  end

  test "provider rejects nested provider facts opts without leaking raw opts" do
    test_pid = self()

    emit_event_fn = fn level, event, fields ->
      send(test_pid, {:readiness_evidence_event, level, event, fields})
    end

    issue = %Issue{
      id: "ISSUE-1",
      workflow: %{
        "change_proposal" => %{
          "url" => "https://example.test/pulls/123"
        }
      }
    }

    assert %{} ==
             EvidenceProvider.evidence(
               issue,
               %{workflow_settings: %{repo: %{provider: "fake"}}},
               %{},
               emit_event_fn: emit_event_fn,
               provider_facts_opts: [:invalid_entry]
             )

    assert_receive {:readiness_evidence_event, :warning, :coding_pr_delivery_readiness_evidence_provider_error,
                    %{
                      component: "workflow.extensions.coding_pr_delivery.readiness.evidence_provider",
                      error_code: "coding_pr_delivery_readiness_evidence_provider_error",
                      operation: "evidence",
                      payload_summary: %{
                        reason: :invalid_provider_facts_options,
                        value_type: :list
                      }
                    }}
  end
end
