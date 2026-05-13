defmodule SymphonyElixir.OrchestratorRoutePolicyTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Orchestrator.Dispatch
  alias SymphonyElixir.Orchestrator.Events, as: OrchestratorEvents
  alias SymphonyElixir.Orchestrator.Runtime, as: OrchestratorRuntime
  alias SymphonyElixir.Workflow.RoutePolicy, as: WorkflowRoutePolicy

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

  test "transition routes confirm the target route and skip dispatch" do
    write_workflow_file!(
      Workflow.workflow_file_path(),
      tapd_route_policy_workflow_config(
        tracker_policy_by_route_key: %{
          "planning" => %{"action" => "transition", "transition_target" => "review"}
        }
      )
    )

    issue = tapd_issue("status_4", planning: %{action: :transition, transition_target: :review})
    refreshed_issue = tapd_issue("status_5", planning: %{action: :transition, transition_target: :review})

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

    assert hd(recent_issue_events(issue))["target_route"] == "review"
    assert hd(recent_issue_events(issue))["target_state"] == "status_5"
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
      assert {:error, {:route_transition_unconfirmed, "status_5", :developing}} =
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
      assert {:error, {:route_transition_failed, :planning, :developing, "developing", :tapd_denied}} =
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

  defp recent_issue_events(issue) do
    EventStore.recent_issue_events(%{
      issue_id: issue.id,
      issue_identifier: issue.identifier
    })
  end

  defp prepare_issue_for_dispatch(issue, fetcher, state_updater) do
    Dispatch.prepare_issue_for_dispatch(
      issue,
      fetcher,
      state_updater,
      OrchestratorRuntime.dispatch_context(),
      emit_route_transition: &OrchestratorEvents.emit_route_transition/7
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
end
