defmodule Mix.Tasks.ChangeProposal.ReconcileTest do
  use SymphonyElixir.TestSupport

  import ExUnit.CaptureIO

  alias Mix.Tasks.ChangeProposal.Reconcile, as: ChangeProposalReconcileTask

  setup do
    Mix.Task.reenable("change_proposal.reconcile")
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_repo_provider_pr)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_issue_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_review_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_reviews)
      Application.delete_env(:symphony_elixir, :memory_repo_change_proposal_checks)
      Application.delete_env(:symphony_elixir, :memory_tracker_issue_state_overrides)
      Mix.Task.reenable("change_proposal.reconcile")
    end)

    :ok
  end

  test "prints help" do
    output = capture_io(fn -> ChangeProposalReconcileTask.run(["--help"]) end)

    assert output =~ "mix change_proposal.reconcile"
    assert output =~ "--confirm-state-write"
    assert output =~ "--issue <id>"
  end

  test "rejects missing issue id" do
    assert_raise Mix.Error, ~r/--issue is required/, fn ->
      capture_io(fn ->
        ChangeProposalReconcileTask.run(["--json"])
      end)
    end
  end

  test "runs dry-run one-shot reconciliation as JSON" do
    write_ready_workflow!("issue-task-dry-run")
    put_ready_repo_provider_payloads()

    output =
      capture_io(fn ->
        ChangeProposalReconcileTask.run(["--issue", "issue-task-dry-run", "--json"])
      end)

    payload = Jason.decode!(output)

    assert payload["ok"] == true
    assert payload["mode"] == "dry_run"
    assert payload["issue_id"] == "issue-task-dry-run"
    assert payload["before_state"] == "In Review"
    assert payload["after_state"] == "In Review"
    assert payload["decision"]["reason"] == "ready_to_land"
    assert payload["transition"]["skip_reason"] == "dry_run"

    refute_receive {:memory_tracker_state_update, "issue-task-dry-run", _state}, 50
  end

  defp write_ready_workflow!(issue_id) do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_provider: %{
        "persist_state_updates" => true,
        "issues" => [
          %{
            "id" => issue_id,
            "identifier" => "MEM-TASK-DRY-RUN",
            "title" => "Ready change proposal",
            "state" => "In Review",
            "branch_name" => "feature/task-dry-run",
            "description" => "",
            "priority" => 0,
            "labels" => []
          }
        ]
      },
      tracker_active_states: ["Todo", "In Progress", "Merging", "Rework"],
      tracker_terminal_states: ["Done", "Canceled"],
      tracker_state_phase_map: %{
        "Todo" => "todo",
        "In Progress" => "in_progress",
        "In Review" => "human_review",
        "Merging" => "merging",
        "Rework" => "rework",
        "Done" => "done",
        "Canceled" => "canceled"
      },
      tracker_raw_state_by_route_key: %{
        "planning" => "Todo",
        "developing" => "In Progress",
        "review" => "In Review",
        "merging" => "Merging",
        "rework" => "Rework",
        "resolved" => "Done",
        "rejected" => "Canceled"
      },
      repo_provider_kind: "memory",
      repo_provider_repository: "acme/widgets",
      workflow_reconciliation: %{
        "change_proposal" => %{
          "enabled" => true,
          "candidates" => %{
            "discovery" => "runtime_targeted",
            "source_routes" => ["review"],
            "max_processed_issues_per_cycle" => 25
          },
          "gates" => %{
            "approval_required" => true,
            "passing_checks_required" => true,
            "mergeable_required" => true
          },
          "outcome_routes" => %{
            "ready" => "merging",
            "changes_requested" => "rework",
            "failed_checks" => "rework",
            "already_merged" => "resolved"
          },
          "thresholds" => %{
            "failed_checks_confirmation_count" => 2
          }
        }
      }
    )
  end

  defp put_ready_repo_provider_payloads do
    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, %{
      "number" => 35,
      "url" => "https://example.test/acme/widgets/-/pulls/35",
      "state" => "OPEN",
      "headRefName" => "feature/ready",
      "headRefOid" => "abc123",
      "mergeable" => "MERGEABLE",
      "mergeStateStatus" => "CLEAN"
    })

    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [])
    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [])

    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [
      %{
        "state" => "APPROVED",
        "user" => %{"login" => "reviewer"},
        "submitted_at" => "2026-05-12T00:00:00Z"
      }
    ])

    Application.put_env(:symphony_elixir, :memory_repo_change_proposal_checks, [
      %{"name" => "ci", "status" => "completed", "conclusion" => "success"}
    ])
  end
end
