defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShotTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.KnownTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Probe

  setup do
    Application.put_env(:symphony_elixir, :memory_tracker_recipient, self())

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_repo_provider_pr)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_issue_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_review_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_reviews)
      Application.delete_env(:symphony_elixir, :memory_repo_change_proposal_checks)
      Application.delete_env(:symphony_elixir, :memory_tracker_issue_state_overrides)
    end)

    :ok
  end

  test "dry-run one-shot processes one runtime targeted issue without writing tracker state" do
    issue =
      memory_issue(%{
        "id" => "issue-one-shot-dry-run",
        "identifier" => "MEM-ONE-SHOT-DRY-RUN",
        "title" => "Ready change proposal",
        "state" => "In Review",
        "branch_name" => "feature/one-shot-dry-run"
      })

    write_memory_reconciliation_workflow!([issue])
    put_ready_repo_provider_payloads()

    report = OneShot.run(issue_id: "issue-one-shot-dry-run")

    assert report.ok
    assert report.mode == "dry_run"
    assert report.shadow["prefix"] == "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]"
    assert report.shadow["mode"] == "shadow_no_write"
    assert report.shadow["run_id"] =~ ~r/^shadow-/
    assert report.shadow["authority"] == "diagnostic_only"
    assert report.shadow["canonical_authority"] == false
    assert "diagnostic_logs" in report.shadow["allowed_destinations"]
    assert report.candidate_discovery == "runtime_targeted"
    assert report.before_state == "In Review"
    assert report.after_state == "In Review"
    refute report.state_changed
    assert report.decision["reason"] == "ready_to_land"
    assert report.transition["event"] == "change_proposal_transition_skipped"
    assert report.transition["skip_reason"] == "dry_run"
    assert report.reconciliation["candidate_fetch_mode"] == "targeted_issue_ids"

    refute_receive {:memory_tracker_state_update, "issue-one-shot-dry-run", _state}, 50
    assert {:ok, [%Issue{state: "In Review"}]} = Tracker.fetch_issue_states_by_ids(["issue-one-shot-dry-run"])

    text = OneShot.format_text(report)

    for line <- String.split(String.trim(text), "\n") do
      assert String.starts_with?(line, "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]")
      assert line =~ "shadow_run_id=#{report.shadow["run_id"]}"
      assert line =~ "shadow_authority=diagnostic_only"
    end
  end

  test "confirmed one-shot writes through normal reconciliation preconditions" do
    issue =
      memory_issue(%{
        "id" => "issue-one-shot-write",
        "identifier" => "MEM-ONE-SHOT-WRITE",
        "title" => "Ready change proposal",
        "state" => "In Review",
        "branch_name" => "feature/one-shot-write"
      })

    write_memory_reconciliation_workflow!([issue])
    put_ready_repo_provider_payloads()

    report = OneShot.run(issue_id: "issue-one-shot-write", confirm_state_write: true)

    assert report.ok
    assert report.mode == "state_write"
    assert report.shadow == nil
    refute OneShot.format_text(report) =~ "[SHADOW_MODE_ONLY - NO PRODUCTION WRITE]"
    assert report.before_state == "In Review"
    assert report.after_state == "Merging"
    assert report.state_changed
    assert report.decision["reason"] == "ready_to_land"
    assert report.transition["event"] == "change_proposal_transition_succeeded"

    assert_receive {:memory_tracker_state_update, "issue-one-shot-write", "Merging"}
    assert {:ok, [%Issue{state: "Merging"}]} = Tracker.fetch_issue_states_by_ids(["issue-one-shot-write"])
  end

  test "dry-run one-shot restores persisted known target from extension state" do
    issue =
      memory_issue(%{
        "id" => "issue-one-shot-known-target",
        "identifier" => "MEM-ONE-SHOT-KNOWN-TARGET",
        "title" => "Ready change proposal with persisted target",
        "state" => "In Review"
      })

    write_memory_reconciliation_workflow!([issue])

    {:ok, registry} = KnownTarget.Registry.start_link(name: nil, workflow_scope: workflow_scope())

    assert {:ok, _target} =
             KnownTarget.Registry.register(
               %{
                 "issue_id" => "issue-one-shot-known-target",
                 "tracker_kind" => "memory",
                 "repo_provider_kind" => "memory",
                 "repository" => "acme/widgets",
                 "number" => "35",
                 "url" => "https://example.test/acme/widgets/-/pulls/35"
               },
               server: registry,
               now_ms: 1_000
             )

    GenServer.stop(registry)

    put_ready_repo_provider_payloads()

    report = OneShot.run(issue_id: "issue-one-shot-known-target")

    assert report.ok
    assert report.mode == "dry_run"
    assert report.before_state == "In Review"
    assert report.after_state == "In Review"
    assert report.decision["reason"] == "ready_to_land"
    assert report.transition["event"] == "change_proposal_transition_skipped"
    refute report.state_changed
  end

  test "one-shot report fails before reconciliation when change proposal config is disabled" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      repo_provider_kind: "memory",
      tracker_provider: %{"issues" => []}
    )

    report = OneShot.run(issue_id: "issue-disabled")

    refute report.ok
    assert Enum.find(report.probes, &(&1.id == "config-validation")).error =~ "disabled"
    assert Enum.find(report.probes, &(&1.id == "targeted-reconcile")).ok == false
  end

  test "one-shot returns bounded report for invalid options" do
    report = OneShot.run([:not_a_keyword])

    refute report.ok
    assert report.mode == "invalid"
    assert [%{id: "options", error: error}] = report.probes
    assert error =~ "code=invalid_one_shot_options"
    assert error =~ "value_type=list"
    refute error =~ "not_a_keyword"
  end

  test "probe exception diagnostics do not expose exception messages" do
    {probe, {:error, %RuntimeError{}}} =
      Probe.run("bounded-probe", fn -> 1 end, fn ->
        raise RuntimeError, "secret provider payload"
      end)

    refute probe.ok
    assert probe.error =~ "exception=RuntimeError"
    refute probe.error =~ "secret provider payload"
  end

  defp write_memory_reconciliation_workflow!(issues) do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "memory",
      tracker_provider: %{
        "persist_state_updates" => true,
        "issues" => issues
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

  defp memory_issue(attrs) when is_map(attrs) do
    Map.merge(
      %{
        "description" => "",
        "priority" => 0,
        "labels" => []
      },
      attrs
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

  defp workflow_scope do
    Config.settings!()
    |> RuntimeContext.new!(%{})
    |> Map.fetch!(:workflow_scope)
  end
end
