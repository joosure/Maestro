defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoff
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  setup do
    if Process.whereis(Store), do: Store.reset()
    :ok
  end

  @workflow %{
    profile_kind: "coding_pr_delivery",
    profile_options: %{"requirements" => %{"change_proposal" => true}},
    raw_state_by_route_key: %{review: "In Review", developing: "In Progress"},
    state_phase_map: %{"In Review" => "human_review", "In Progress" => "in_progress"}
  }

  test "review_target? matches the coding PR delivery review route" do
    assert ReviewHandoff.review_target?(@workflow, "In Review")
    assert ReviewHandoff.governed_target?(@workflow, "In Review")
    refute ReviewHandoff.review_target?(@workflow, "In Progress")
    refute ReviewHandoff.review_target?(%{@workflow | profile_kind: "triage"}, "In Review")
  end

  test "validate accepts complete structured handoff evidence and tracker attachment" do
    assert :ok =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: ready_evidence()
             )
  end

  test "validate blocks when only human-readable workpad Markdown appears complete" do
    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()], complete_markdown_workpad()),
               target_state_name: "In Review",
               evidence: ready_evidence_without("workpad")
             )

    assert details["gate"] == "human_review"
    assert details["status"] == "blocked"
    assert details["target_state"] == "In Review"
    assert "workpad_record_missing" in details["reason_codes"]

    assert Enum.any?(details["missing_evidence"], &(Map.get(&1, "code") == "workpad_record_missing"))
  end

  test "validate blocks agent-declared workpad section completion without backend write evidence" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "workpad"], %{
        "status" => "complete",
        "source" => "typed_tool_observed",
        "updated_at" => "2026-05-19T08:04:00Z",
        "sections" => [
          %{"key" => "plan", "status" => "complete"},
          %{"key" => "acceptance_criteria", "status" => "complete"},
          %{"key" => "validation", "status" => "complete"}
        ]
      })

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "workpad_record_untrusted" in details["reason_codes"]
  end

  test "validate blocks stale workpad records written before later handoff evidence" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "workpad", "updated_at"], "2026-05-19T08:00:00Z")
      |> put_in(["observations", "repo", "observed_at"], "2026-05-19T08:01:00Z")
      |> put_in(["observations", "change_proposal", "observed_at"], "2026-05-19T08:02:00Z")
      |> put_in(["observations", "validation", "observed_at"], "2026-05-19T08:03:00Z")
      |> put_in(["observations", "checks", "observed_at"], "2026-05-19T08:04:00Z")
      |> put_in(["observations", "feedback", "observed_at"], "2026-05-19T08:05:00Z")

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "workpad_record_stale" in details["reason_codes"]
  end

  test "validate blocks when change proposal is not linked through structured tracker evidence" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "change_proposal", "linked_to_tracker"], false)

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "change_proposal_tracker_link_missing" in details["reason_codes"]
  end

  test "validate blocks stale validation head" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "repo", "head_sha"], "new-head")
      |> put_in(["observations", "change_proposal", "head_sha"], "new-head")
      |> put_in(["observations", "validation", "head_sha"], "old-head")
      |> put_in(["observations", "validation", "commands"], [
        %{"command" => "mix test", "exit_code" => 0, "head_sha" => "old-head"}
      ])

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "validation_head_stale" in details["reason_codes"]
  end

  test "validate uses the latest pushed repo head when a change proposal snapshot predates the push" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "repo", "head_sha"], "new-head")
      |> put_in(["observations", "repo", "published_head_sha"], "new-head")
      |> put_in(["observations", "change_proposal", "head_ref"], "feature/demo-18")
      |> put_in(["observations", "change_proposal", "head_sha"], "old-pr-snapshot-head")
      |> put_in(["observations", "validation", "head_sha"], "new-head")
      |> put_in(["observations", "validation", "commands"], [
        %{"command" => "git diff --check", "exit_code" => 0, "head_sha" => "new-head"}
      ])
      |> put_in(["observations", "checks"], %{
        "status" => "not_required",
        "source" => "repo_provider_observed"
      })

    assert :ok =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )
  end

  test "validate blocks provider checks observed for an older head than the pushed repo head" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "repo", "head_sha"], "new-head")
      |> put_in(["observations", "repo", "published_head_sha"], "new-head")
      |> put_in(["observations", "change_proposal", "head_sha"], "old-head")
      |> put_in(["observations", "validation", "head_sha"], "new-head")
      |> put_in(["observations", "validation", "commands"], [
        %{"command" => "git diff --check", "exit_code" => 0, "head_sha" => "new-head"}
      ])
      |> put_in(["observations", "checks", "head_sha"], "old-head")

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "provider_checks_head_stale" in details["reason_codes"]
  end

  test "validate accepts not-required provider checks observed after the latest pushed repo head" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "repo", "head_sha"], "new-head")
      |> put_in(["observations", "repo", "published_head_sha"], "new-head")
      |> put_in(["observations", "repo", "observed_at"], "2026-05-19T08:01:00Z")
      |> put_in(["observations", "change_proposal", "head_sha"], "old-pr-snapshot-head")
      |> put_in(["observations", "change_proposal", "observed_at"], "2026-05-19T08:00:00Z")
      |> put_in(["observations", "validation", "head_sha"], "new-head")
      |> put_in(["observations", "validation", "commands"], [
        %{"command" => "git diff --check", "exit_code" => 0, "head_sha" => "new-head"}
      ])
      |> put_in(["observations", "checks"], %{
        "status" => "not_required",
        "source" => "repo_provider_observed",
        "head_sha" => "old-pr-snapshot-head",
        "observed_at" => "2026-05-19T08:02:00Z"
      })

    assert :ok =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )
  end

  test "validate blocks not-required provider checks observed before the latest pushed repo head" do
    evidence =
      ready_evidence()
      |> put_in(["observations", "repo", "head_sha"], "new-head")
      |> put_in(["observations", "repo", "published_head_sha"], "new-head")
      |> put_in(["observations", "repo", "observed_at"], "2026-05-19T08:02:00Z")
      |> put_in(["observations", "change_proposal", "head_sha"], "old-pr-snapshot-head")
      |> put_in(["observations", "change_proposal", "observed_at"], "2026-05-19T08:00:00Z")
      |> put_in(["observations", "validation", "head_sha"], "new-head")
      |> put_in(["observations", "validation", "commands"], [
        %{"command" => "git diff --check", "exit_code" => 0, "head_sha" => "new-head"}
      ])
      |> put_in(["observations", "checks"], %{
        "status" => "not_required",
        "source" => "repo_provider_observed",
        "head_sha" => "old-pr-snapshot-head",
        "observed_at" => "2026-05-19T08:01:00Z"
      })

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               evidence: evidence
             )

    assert "provider_checks_observation_stale" in details["reason_codes"]
  end

  test "validate scopes stored evidence to the current run when run_id is present" do
    Store.record("DEMO-18", ready_evidence())

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               run_id: "run-new"
             )

    assert "workpad_record_missing" in details["reason_codes"]

    Store.record(Store.scope_issue_keys("run-new", "DEMO-18"), ready_evidence())

    assert :ok =
             ReviewHandoff.validate(
               @workflow,
               issue([change_proposal_attachment()]),
               target_state_name: "In Review",
               run_id: "run-new"
             )
  end

  defp issue(attachments, workpad_body \\ nil) do
    comments =
      if is_binary(workpad_body) do
        [
          %{
            "id" => "comment-workpad",
            "body" => workpad_body,
            "resolvedAt" => nil,
            "createdAt" => "2026-05-19T00:00:00Z",
            "updatedAt" => "2026-05-19T01:00:00Z"
          }
        ]
      else
        []
      end

    %{
      "id" => "issue-1",
      "identifier" => "DEMO-18",
      "comments" => %{"nodes" => comments},
      "attachments" => %{"nodes" => attachments}
    }
  end

  defp change_proposal_attachment do
    %{
      "id" => "attachment-1",
      "title" => "Pull request",
      "url" => "https://github.com/example/repo/pull/42",
      "sourceType" => "github"
    }
  end

  defp ready_evidence_without(key) do
    update_in(ready_evidence(), ["observations"], &Map.delete(&1, key))
  end

  defp ready_evidence do
    %{
      "observations" => %{
        "workpad" => %{
          "status" => "updated",
          "source" => "typed_tool_observed",
          "comment_id" => "comment-workpad",
          "updated_at" => "2026-05-19T08:06:00Z"
        },
        "repo" => %{
          "change_kind" => "code_change",
          "source" => "repo_observed",
          "head_ref" => "feature/demo-18",
          "head_sha" => "head-1",
          "commits" => [%{"sha" => "head-1"}],
          "observed_at" => "2026-05-19T08:01:00Z"
        },
        "change_proposal" => %{
          "status" => "updated",
          "source" => "repo_provider_observed",
          "url" => "https://github.com/example/repo/pull/42",
          "head_ref" => "feature/demo-18",
          "head_sha" => "head-1",
          "linked_to_tracker" => true,
          "observed_at" => "2026-05-19T08:02:00Z"
        },
        "validation" => %{
          "status" => "passed",
          "source" => "typed_tool_observed",
          "head_sha" => "head-1",
          "commands" => [%{"command" => "mix test", "exit_code" => 0, "head_sha" => "head-1"}],
          "observed_at" => "2026-05-19T08:03:00Z"
        },
        "checks" => %{
          "status" => "passed",
          "source" => "repo_provider_observed",
          "head_sha" => "head-1",
          "observed_at" => "2026-05-19T08:04:00Z"
        },
        "feedback" => %{
          "status" => "clear",
          "source" => "repo_provider_observed",
          "actionable_count" => 0,
          "observed_at" => "2026-05-19T08:05:00Z"
        }
      }
    }
  end

  defp complete_markdown_workpad do
    """
    ## CodeBuddy Code Workpad

    ### Plan

    - [x] Build the change

    ### Acceptance Criteria

    - [x] Criteria verified

    ### Validation

    - [x] mix test
    """
  end
end
