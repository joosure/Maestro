defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffStructuredPlanTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoff
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @enabled_gate "workflow.structured_execution_plan.enabled"
  @review_handoff_gate "workflow.structured_execution_plan.review_handoff_required"
  @plan_id "plan-review-handoff-1"
  @run_id "run-review-handoff-1"
  @issue_id "DEMO-18"
  @profile %{"kind" => "coding_pr_delivery", "version" => 1}
  @created_at "2026-05-20T00:00:00Z"

  setup do
    store = start_supervised!({Store, name: nil})
    {:ok, store: store}
  end

  @workflow %{
    profile_kind: "coding_pr_delivery",
    profile_version: 1,
    profile_options: %{"requirements" => %{"change_proposal" => true}},
    raw_state_by_route_key: %{review: "In Review", developing: "In Progress"},
    state_phase_map: %{"In Review" => "human_review", "In Progress" => "in_progress"}
  }

  test "gate disabled leaves existing review handoff behavior unchanged without a plan", %{store: store} do
    assert :ok =
             ReviewHandoff.validate(
               @workflow,
               issue(),
               target_state_name: "In Review",
               evidence: ready_evidence(),
               structured_execution_plan: %{server: store, run_id: @run_id, route_key: "developing", workflow_profile: @profile}
             )
  end

  test "missing plan blocks review handoff when plan gate is enabled", %{store: store} do
    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(), gated_opts(store))

    assert details["status"] == "blocked"
    assert "structured_plan_missing" in details["reason_codes"]
  end

  test "review handoff gate requires structured plans to be enabled", %{store: store} do
    opts =
      gated_opts(store,
        gates: %{
          @enabled_gate => false,
          @review_handoff_gate => true
        }
      )

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(), opts)

    assert "structured_plan_gate_misconfigured" in details["reason_codes"]
  end

  test "provider-native task completion without evidence does not unblock handoff", %{store: store} do
    create_plan!(
      store,
      complete_plan(
        items:
          complete_items()
          |> replace_item("repo.push", fn item -> %{item | "status" => "complete", "evidence_refs" => []} end)
      )
    )

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(), gated_opts(store))

    assert "structured_plan_implementation_incomplete" in details["reason_codes"]
  end

  test "manually edited Workpad checkbox does not satisfy structured handoff evidence", %{store: store} do
    create_plan!(
      store,
      complete_plan(
        items:
          complete_items()
          |> replace_item("tracker.handoff", fn item -> %{item | "status" => "complete", "evidence_refs" => []} end)
      )
    )

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(complete_markdown_workpad()), gated_opts(store))

    assert "structured_plan_handoff_record_incomplete" in details["reason_codes"]
  end

  test "new commit after validation stales dependent structured plan items", %{store: store} do
    create_plan!(
      store,
      complete_plan(
        head_sha: "new-head",
        items:
          complete_items(
            repo_head: "new-head",
            repo_observed_at: "2026-05-20T08:07:00Z",
            dependent_head: "old-head",
            dependent_observed_at: "2026-05-20T08:03:00Z"
          )
      )
    )

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(), gated_opts(store, evidence: ready_evidence("new-head")))

    assert "structured_plan_validation_stale" in details["reason_codes"]
    assert "structured_plan_change_proposal_checks_stale" in details["reason_codes"]
    assert "structured_plan_feedback_stale" in details["reason_codes"]
    assert "structured_plan_handoff_record_stale" in details["reason_codes"]
  end

  test "head SHA mismatch between readiness evidence and canonical plan blocks handoff", %{store: store} do
    create_plan!(store, complete_plan(head_sha: "old-head"))

    assert {:error, {:review_handoff_not_ready, details}} =
             ReviewHandoff.validate(@workflow, issue(), gated_opts(store, evidence: ready_evidence("new-head")))

    assert "structured_plan_head_mismatch" in details["reason_codes"]
  end

  test "superseded and closed plans fail closed when explicitly selected", %{store: store} do
    for {status, reason_code} <- [{"superseded", "structured_plan_superseded"}, {"closed", "structured_plan_closed"}] do
      plan_id = "#{@plan_id}-#{status}"
      create_plan!(store, complete_plan(plan_id: plan_id, status: status))

      assert {:error, {:review_handoff_not_ready, details}} =
               ReviewHandoff.validate(@workflow, issue(), gated_opts(store, structured_execution_plan: %{plan_id: plan_id}))

      assert reason_code in details["reason_codes"]
    end
  end

  test "complete canonical plan and readiness evidence allows review handoff", %{store: store} do
    create_plan!(store, complete_plan())

    assert :ok = ReviewHandoff.validate(@workflow, issue(), gated_opts(store))
  end

  defp gated_opts(store, overrides \\ []) do
    structured_plan =
      %{
        server: store,
        run_id: @run_id,
        route_key: "developing",
        workflow_profile: @profile
      }
      |> Map.merge(Keyword.get(overrides, :structured_execution_plan, %{}))

    [
      target_state_name: "In Review",
      run_id: @run_id,
      issue_key: @issue_id,
      evidence: Keyword.get(overrides, :evidence, ready_evidence()),
      gates:
        Keyword.get(overrides, :gates, %{
          @enabled_gate => true,
          @review_handoff_gate => true
        }),
      structured_execution_plan: structured_plan
    ]
  end

  defp create_plan!(store, plan) do
    assert {:ok, _plan} = Store.create(plan, server: store)
  end

  defp complete_plan(opts \\ []) do
    plan_id = Keyword.get(opts, :plan_id, @plan_id)
    head_sha = Keyword.get(opts, :head_sha, "head-1")

    %{
      "schema" => "workflow.execution_plan.v1",
      "plan_id" => plan_id,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "issue_identifier" => @issue_id,
      "tracker_kind" => "linear",
      "workflow_profile" => @profile,
      "route_key" => "developing",
      "lifecycle_phase" => "in_progress",
      "status" => Keyword.get(opts, :status, "active"),
      "items" => Keyword.get(opts, :items, complete_items(repo_head: head_sha, dependent_head: head_sha)),
      "created_at" => @created_at,
      "updated_at" => @created_at,
      "revision" => 1
    }
  end

  defp complete_items(opts \\ []) do
    repo_head = Keyword.get(opts, :repo_head, "head-1")
    dependent_head = Keyword.get(opts, :dependent_head, repo_head)
    repo_observed_at = Keyword.get(opts, :repo_observed_at, "2026-05-20T08:01:00Z")
    dependent_observed_at = Keyword.get(opts, :dependent_observed_at, nil)

    [
      item("repo.push", "repo_push", ["branch", "head_sha", "published_head_sha"],
        payload: %{"branch" => "feature/demo", "head_sha" => repo_head, "published_head_sha" => repo_head},
        observed_at: repo_observed_at
      ),
      item("validation.diff", "repo_diff", ["check"],
        kind: "validation",
        payload: %{"check" => true, "head_sha" => dependent_head},
        observed_at: dependent_observed_at || "2026-05-20T08:03:00Z"
      ),
      item("repo.change_proposal", "repo_create_or_update_change_proposal", ["url", "number"],
        payload: %{
          "url" => "https://github.com/example/repo/pull/42",
          "number" => "42",
          "head_sha" => dependent_head
        },
        observed_at: "2026-05-20T08:02:00Z"
      ),
      item("tracker.linkage", "tracker_attach_change_proposal", ["linked_to_tracker", "url"],
        payload: %{
          "linked_to_tracker" => true,
          "url" => "https://github.com/example/repo/pull/42",
          "attachment_id" => "attachment-1"
        },
        observed_at: "2026-05-20T08:02:30Z"
      ),
      item("repo.checks", "repo_read_change_proposal_checks", ["status"],
        kind: "validation",
        payload: %{"status" => "passed", "head_sha" => dependent_head},
        observed_at: dependent_observed_at || "2026-05-20T08:04:00Z"
      ),
      item("repo.feedback", "repo_read_change_proposal_discussion", ["status"],
        kind: "validation",
        payload: %{"status" => "clear", "actionable_count" => 0},
        observed_at: dependent_observed_at || "2026-05-20T08:05:00Z"
      ),
      item("tracker.handoff", "tracker_upsert_workpad", ["workpad_id"],
        kind: "handoff_record",
        payload: %{"workpad_id" => "linear:issue:issue-1:workpad", "updated" => true},
        observed_at: dependent_observed_at || "2026-05-20T08:06:00Z"
      )
    ]
  end

  defp item(item_id, evidence_kind, required_fields, opts) do
    payload = Keyword.fetch!(opts, :payload)
    observed_at = Keyword.fetch!(opts, :observed_at)

    %{
      "item_id" => item_id,
      "parent_item_id" => nil,
      "title" => item_id,
      "kind" => Keyword.get(opts, :kind, "tool_evidence"),
      "status" => "complete",
      "required" => true,
      "criticality" => "handoff_blocking",
      "owned_by" => "backend",
      "source" => "profile",
      "depends_on" => [],
      "evidence_requirements" => [
        %{
          "evidence_kind" => evidence_kind,
          "required_fields" => required_fields,
          "trust_classes" => ["tool_generated"]
        }
      ],
      "evidence_refs" => [evidence_ref(evidence_kind, payload, observed_at)],
      "created_at" => @created_at,
      "updated_at" => observed_at,
      "revision" => 1
    }
  end

  defp evidence_ref(evidence_kind, payload, observed_at) do
    %{
      "evidence_id" => "evidence-#{evidence_kind}",
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => evidence_kind,
      "run_id" => @run_id,
      "issue_id" => @issue_id,
      "observed_at" => observed_at,
      "payload" => payload
    }
  end

  defp replace_item(items, item_id, fun) do
    Enum.map(items, fn item ->
      if Map.get(item, "item_id") == item_id, do: fun.(item), else: item
    end)
  end

  defp issue(workpad_body \\ nil) do
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
      "id" => @issue_id,
      "identifier" => @issue_id,
      "state" => %{"name" => "In Progress"},
      "comments" => %{"nodes" => comments},
      "attachments" => %{"nodes" => [change_proposal_attachment()]}
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

  defp ready_evidence(head_sha \\ "head-1") do
    %{
      "observations" => %{
        "workpad" => %{
          "status" => "updated",
          "source" => "typed_tool_observed",
          "workpad_id" => "linear:issue:issue-1:workpad",
          "updated_at" => "2026-05-20T08:06:30Z"
        },
        "repo" => %{
          "change_kind" => "code_change",
          "source" => "repo_observed",
          "head_ref" => "feature/demo",
          "head_sha" => head_sha,
          "published_head_sha" => head_sha,
          "commits" => [%{"sha" => head_sha}],
          "observed_at" => "2026-05-20T08:01:00Z"
        },
        "change_proposal" => %{
          "status" => "updated",
          "source" => "repo_provider_observed",
          "url" => "https://github.com/example/repo/pull/42",
          "head_ref" => "feature/demo",
          "head_sha" => head_sha,
          "linked_to_tracker" => true,
          "observed_at" => "2026-05-20T08:02:00Z"
        },
        "validation" => %{
          "status" => "passed",
          "source" => "typed_tool_observed",
          "head_sha" => head_sha,
          "commands" => [%{"command" => "git diff --check", "exit_code" => 0, "head_sha" => head_sha}],
          "observed_at" => "2026-05-20T08:03:00Z"
        },
        "checks" => %{
          "status" => "passed",
          "source" => "repo_provider_observed",
          "head_sha" => head_sha,
          "observed_at" => "2026-05-20T08:04:00Z"
        },
        "feedback" => %{
          "status" => "clear",
          "source" => "repo_provider_observed",
          "actionable_count" => 0,
          "observed_at" => "2026-05-20T08:05:00Z"
        }
      }
    }
  end

  defp complete_markdown_workpad do
    """
    ## Workpad

    ### Plan

    - [x] Build the change

    ### Acceptance Criteria

    - [x] Criteria verified

    ### Validation

    - [x] git diff --check
    """
  end
end
