defmodule SymphonyElixir.TrackerConfigTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Tracker.Config, as: TrackerConfig

  test "linear tracker accepts nested auth provider and lifecycle config" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_endpoint: "https://api.linear.app/graphql",
      tracker_auth: %{"api_key" => "nested-token"},
      tracker_provider: %{"project_slug" => "nested-project", "assignee" => "me"},
      tracker_lifecycle: %{
        "active_states" => ["Todo", "In Progress"],
        "terminal_states" => ["Done"],
        "state_phase_map" => %{
          "Todo" => "todo",
          "In Progress" => "in_progress",
          "Done" => "done"
        }
      },
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil
    )

    assert :ok = Config.validate!()

    tracker = Config.settings!().tracker
    assert match?(%TrackerConfig{}, TrackerConfig.current!())

    assert TrackerConfig.api_key(tracker) == "nested-token"
    assert TrackerConfig.provider(tracker)["project_slug"] == "nested-project"
    assert TrackerConfig.provider(tracker)["assignee"] == "me"
    assert TrackerConfig.active_states(tracker) == ["Todo", "In Progress"]
    assert tracker.auth["api_key"] == "nested-token"
    assert tracker.provider["project_slug"] == "nested-project"
    assert tracker.provider["assignee"] == "me"
    assert tracker.lifecycle["terminal_states"] == ["Done"]
  end

  test "tapd tracker accepts nested auth provider platform and lifecycle config" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "tapd",
      tracker_endpoint: "https://api.tapd.cn",
      tracker_auth: %{"api_key" => "tapd-user", "api_secret" => "tapd-secret"},
      tracker_provider: %{"platform" => %{"workspace_id" => "53000000", "comment_author" => "robot"}},
      tracker_lifecycle: %{
        "active_states" => ["planning"],
        "terminal_states" => ["resolved"],
        "state_phase_map" => %{"planning" => "todo", "resolved" => "done"}
      },
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil,
      tracker_platform: %{}
    )

    assert :ok = Config.validate!()
    assert Tracker.project_id() == "53000000"

    tool_names =
      [dynamic_tool_source: SymphonyElixir.Tracker.DynamicToolSource]
      |> DynamicTool.tool_specs()
      |> Enum.map(&Map.fetch!(&1, "name"))

    refute "tapd_api" in tool_names
    assert "tapd_issue_snapshot" in tool_names
    assert "tapd_move_issue" in tool_names
    assert "tapd_upsert_workpad" in tool_names
    assert "tapd_attach_change_proposal" in tool_names
    assert "tapd_upsert_comment" in tool_names
    assert "tapd_create_follow_up_story" in tool_names
    assert "tapd_read_story_relations" in tool_names
    assert "tapd_add_story_relation" in tool_names
    assert "tapd_read_story_dependencies" in tool_names
    assert "tapd_save_story_dependency" in tool_names

    tracker = Config.settings!().tracker
    assert get_in(TrackerConfig.provider(tracker), ["platform", "workspace_id"]) == "53000000"
    assert tracker.provider["platform"]["comment_author"] == "robot"
    assert tracker.auth["api_secret"] == "tapd-secret"
  end

  test "tracker config exposes normalized tracker metadata and lifecycle accessors" do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "linear",
      tracker_auth: %{"api_key" => "nested-token"},
      tracker_provider: %{"project_slug" => "nested-project"},
      tracker_lifecycle: %{
        "active_states" => ["Todo", "In Progress"],
        "terminal_states" => ["Done"],
        "state_phase_map" => %{
          "Todo" => "todo",
          "In Progress" => "in_progress",
          "Done" => "done"
        }
      },
      tracker_api_token: nil,
      tracker_project_slug: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil,
      tracker_state_phase_map: nil
    )

    tracker = Config.settings!().tracker

    assert TrackerConfig.current!() |> TrackerConfig.kind() == "linear"
    assert TrackerConfig.kind(tracker) == "linear"
    assert TrackerConfig.current!() |> TrackerConfig.active_states() == ["Todo", "In Progress"]
    assert TrackerConfig.active_states(tracker) == ["Todo", "In Progress"]
    assert TrackerConfig.current!() |> TrackerConfig.terminal_states() == ["Done"]
    assert TrackerConfig.terminal_states(tracker) == ["Done"]
    assert TrackerConfig.current!() |> TrackerConfig.state_phase_map() |> Map.get("done") == "done"
    assert TrackerConfig.state_phase_map(tracker)["in progress"] == "in_progress"
  end
end
