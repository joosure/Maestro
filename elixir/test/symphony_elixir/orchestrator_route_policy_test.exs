defmodule SymphonyElixir.OrchestratorRoutePolicyTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Events, as: OrchestratorEvents
  alias SymphonyElixir.Orchestrator.Runtime, as: OrchestratorRuntime
  alias SymphonyElixir.Tracker.Linear.WorkflowConfig, as: LinearWorkflowConfig
  alias SymphonyElixir.Workflow.RoutePolicy, as: WorkflowRoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  test "wait routes skip dispatch without refreshing or writing state" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("status_5")

    fetcher = fn _issue_ids ->
      send(self(), :wait_fetch_called)
      {:ok, []}
    end

    state_updater = fn _issue_id, _state_name ->
      send(self(), :wait_update_called)
      :ok
    end

    assert {:skip, %Issue{state: "status_5"}} =
             prepare_issue_for_dispatch(issue, fetcher, state_updater)

    refute_received :wait_fetch_called
    refute_received :wait_update_called
  end

  test "stop routes skip dispatch without refreshing or writing state" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("resolved")

    fetcher = fn _issue_ids ->
      send(self(), :stop_fetch_called)
      {:ok, []}
    end

    state_updater = fn _issue_id, _state_name ->
      send(self(), :stop_update_called)
      :ok
    end

    assert {:skip, %Issue{state: "resolved"}} =
             prepare_issue_for_dispatch(issue, fetcher, state_updater)

    refute_received :stop_fetch_called
    refute_received :stop_update_called
  end

  test "merge routes dispatch to land flow when only merge evidence is missing" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("merging")

    fetcher = fn _issue_ids ->
      send(self(), :merge_fetch_called)
      {:ok, []}
    end

    state_updater = fn _issue_id, _state_name ->
      send(self(), :merge_update_called)
      :ok
    end

    assert {:ok, %Issue{state: "merging"}} =
             prepare_issue_for_dispatch(issue, fetcher, state_updater, readiness_evidence: %{})

    refute_received :merge_fetch_called
    refute_received :merge_update_called
  end

  test "merge routes dispatch when merge readiness evidence is present" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("merging")

    fetcher = fn _issue_ids ->
      send(self(), :merge_ready_fetch_called)
      {:ok, []}
    end

    state_updater = fn _issue_id, _state_name ->
      send(self(), :merge_ready_update_called)
      :ok
    end

    assert {:ok, %Issue{state: "merging", workflow: workflow}} =
             prepare_issue_for_dispatch(issue, fetcher, state_updater,
               readiness_evidence_fn: fn %Issue{}, _context, facts ->
                 send(self(), {:merge_readiness_evidence_requested, get_in(facts, ["gate", "gate"])})
                 merge_readiness_evidence()
               end
             )

    assert_received {:merge_readiness_evidence_requested, "merge"}
    assert get_in(workflow, [:completion_evidence, :review, :approved]) == true
    assert get_in(workflow, [:completion_evidence, :checks, :passing]) == true

    refute_received :merge_ready_fetch_called
    refute_received :merge_ready_update_called
  end

  test "transition routes confirm the target route and skip dispatch" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition", "transition_target" => "review"}
        }
      )
    )

    issue = tapd_issue("status_4", %{"planning" => %{"action" => "transition", "transition_target" => "review"}})
    refreshed_issue = tapd_issue("status_5", %{"planning" => %{"action" => "transition", "transition_target" => "review"}})

    fetcher = fn ["tapd-route-1"] -> {:ok, [refreshed_issue]} end

    state_updater = fn "tapd-route-1", "status_5" ->
      send(self(), {:transition_update_called, "tapd-route-1", "status_5"})
      :ok
    end

    capture_log(fn ->
      assert {:skip, %Issue{state: "status_5"}} =
               prepare_issue_for_dispatch(issue, fetcher, state_updater)
    end)

    assert_receive {:transition_update_called, "tapd-route-1", "status_5"}

    assert Enum.map(recent_issue_events(issue), & &1["event"]) == [
             "route_transition_succeeded",
             "route_transition_attempted",
             "route_preparation_started"
           ]

    succeeded_event = hd(recent_issue_events(issue))

    assert succeeded_event["target_state"] == "status_5"
    assert succeeded_event["workflow_profile"] == "coding_pr_delivery"
    assert succeeded_event["workflow_profile_version"] == 1
    assert succeeded_event["workflow_route_key"] == "planning"
    assert succeeded_event["workflow_transition_target_route_key"] == "review"
    refute Map.has_key?(succeeded_event, "route_key")
    refute Map.has_key?(succeeded_event, "target_route")
  end

  test "transition mismatches emit route_transition_unconfirmed" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("status_4")
    refreshed_issue = tapd_issue("status_5")

    fetcher = fn ["tapd-route-1"] -> {:ok, [refreshed_issue]} end

    state_updater = fn "tapd-route-1", "developing" ->
      send(self(), {:unconfirmed_update_called, "tapd-route-1", "developing"})
      :ok
    end

    capture_log(fn ->
      assert {:error,
              {:route_transition_unconfirmed, "status_5",
               %RouteRef{
                 profile_kind: "coding_pr_delivery",
                 profile_version: 1,
                 route_key: :developing
               }}} =
               prepare_issue_for_dispatch(issue, fetcher, state_updater)
    end)

    assert_receive {:unconfirmed_update_called, "tapd-route-1", "developing"}

    assert Enum.map(recent_issue_events(issue), & &1["event"]) == [
             "route_transition_unconfirmed",
             "route_transition_attempted",
             "route_preparation_started"
           ]
  end

  test "write failures emit route_transition_failed" do
    write_workflow_file!(Workflow.workflow_file_path(), tapd_route_policy_workflow_config())

    issue = tapd_issue("status_4")

    fetcher = fn _issue_ids ->
      send(self(), :failed_fetch_called)
      {:ok, []}
    end

    state_updater = fn "tapd-route-1", "developing" ->
      send(self(), {:failed_update_called, "tapd-route-1", "developing"})
      {:error, :tapd_denied}
    end

    capture_log(fn ->
      assert {:error,
              {:route_transition_failed,
               %RouteRef{
                 profile_kind: "coding_pr_delivery",
                 profile_version: 1,
                 route_key: :planning
               },
               %RouteRef{
                 profile_kind: "coding_pr_delivery",
                 profile_version: 1,
                 route_key: :developing
               }, "developing", :tapd_denied}} =
               prepare_issue_for_dispatch(issue, fetcher, state_updater)
    end)

    assert_receive {:failed_update_called, "tapd-route-1", "developing"}
    refute_received :failed_fetch_called

    assert Enum.map(recent_issue_events(issue), & &1["event"]) == [
             "route_transition_failed",
             "route_transition_attempted",
             "route_preparation_started"
           ]
  end

  test "linear workflow routes drive backend Todo to In Progress transition" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_api_token: "linear-token",
      tracker_project_slug: "PROJ",
      tracker_raw_state_by_route_key: %{
        "planning" => "Todo",
        "developing" => "In Progress",
        "review" => "In Review",
        "merging" => "Merging",
        "rework" => "Rework",
        "resolved" => "Done",
        "rejected" => "Canceled"
      }
    )

    workflow = Config.settings!().tracker |> LinearWorkflowConfig.global_workflow()
    issue = linear_issue("Todo", workflow)
    refreshed_issue = linear_issue("In Progress", workflow)

    fetcher = fn ["linear-route-1"] -> {:ok, [refreshed_issue]} end

    state_updater = fn "linear-route-1", "In Progress" ->
      send(self(), {:linear_update_called, "linear-route-1", "In Progress"})
      :ok
    end

    capture_log(fn ->
      assert {:ok, %Issue{state: "In Progress"}} =
               prepare_issue_for_dispatch(issue, fetcher, state_updater)
    end)

    assert_receive {:linear_update_called, "linear-route-1", "In Progress"}
  end

  defp recent_issue_events(issue) do
    EventStore.recent_issue_events(%{
      issue_id: issue.id,
      issue_identifier: issue.identifier
    })
  end

  defp prepare_issue_for_dispatch(issue, fetcher, state_updater, opts \\ []) do
    Dispatch.prepare_issue_for_dispatch(
      issue,
      fetcher,
      state_updater,
      OrchestratorRuntime.dispatch_context(),
      Keyword.merge(
        [emit_route_transition: &OrchestratorEvents.emit_route_transition/7],
        opts
      )
    )
  end

  defp tapd_issue(state_name, route_policy_overrides \\ %{}) do
    %Issue{
      id: "tapd-route-1",
      identifier: "TAPD-3001",
      title: "Route policy orchestrator test",
      state: state_name,
      workflow: tapd_workflow(route_policy_overrides)
    }
  end

  defp linear_issue(state_name, workflow) do
    %Issue{
      id: "linear-route-1",
      identifier: "LIN-3001",
      title: "Linear route policy orchestrator test",
      state: state_name,
      lifecycle_phase: Map.get(workflow.state_phase_map, state_name),
      workflow: workflow
    }
  end

  defp tapd_workflow(route_policy_overrides) do
    route_policy_overrides =
      cond do
        is_map(route_policy_overrides) -> route_policy_overrides
        Keyword.keyword?(route_policy_overrides) -> Enum.into(route_policy_overrides, %{})
        true -> %{}
      end

    %{
      active_states: ["status_4", "developing", "merging", "rework"],
      terminal_states: ["resolved", "rejected"],
      state_phase_map: %{
        "status_4" => "todo",
        "developing" => "in_progress",
        "status_5" => "human_review",
        "merging" => "merging",
        "rework" => "rework",
        "resolved" => "done",
        "rejected" => "canceled"
      },
      raw_state_by_route_key: %{
        planning: "status_4",
        developing: "developing",
        review: "status_5",
        merging: "merging",
        rework: "rework",
        resolved: "resolved",
        rejected: "rejected"
      },
      policy_by_route_key: WorkflowRoutePolicy.resolve_policy_by_route_key(route_policy_overrides)
    }
  end

  defp tapd_route_policy_workflow_config(overrides \\ []) do
    Keyword.merge(
      [
        tracker_kind: "tapd",
        tracker_endpoint: nil,
        tracker_api_token: "tapd-user",
        tracker_api_secret: "tapd-secret",
        tracker_project_slug: nil,
        tracker_assignee: nil,
        tracker_active_states: ["status_4", "developing", "merging", "rework"],
        tracker_terminal_states: ["resolved", "rejected"],
        tracker_state_phase_map: %{
          "status_4" => "todo",
          "developing" => "in_progress",
          "status_5" => "human_review",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "done",
          "rejected" => "canceled"
        },
        tracker_raw_state_by_route_key: %{
          "planning" => "status_4",
          "developing" => "developing",
          "review" => "status_5",
          "merging" => "merging",
          "rework" => "rework",
          "resolved" => "resolved",
          "rejected" => "rejected"
        },
        tracker_platform: %{"workspace_id" => "53000000"}
      ],
      overrides
    )
  end

  defp merge_readiness_evidence do
    %{
      change_proposal: %{
        url: "https://cnb.example.test/acme/widgets/-/pulls/36",
        number: "36",
        linked_issue: true,
        tracker_linked: true
      },
      repo: %{head_sha: "abc123", diff_present: true},
      checks: %{read: true, status: "passing", check_summary: "passing", passing: true},
      review: %{approved: true, status: "approved", review_summary: "approved"},
      tracker: %{state: "merging", change_proposal_attached: true, merge_approved: true}
    }
  end
end
