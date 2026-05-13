defmodule SymphonyElixir.TapdNormalizerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Tracker.Tapd.Normalizer

  test "normalizes a TAPD story into the shared issue shape" do
    story = %{
      "id" => "123456",
      "name" => "Implement TAPD adapter",
      "description" => "Add runtime integration",
      "priority" => "3",
      "status" => "developing",
      "workitem_type_id" => "1153070854001000001",
      "label" => "backend, integration ",
      "blocked_by" => [
        %{"id" => "111", "status" => "planning"},
        "222"
      ],
      "created" => "2026-04-01T10:00:00Z",
      "modified" => "2026-04-02T12:30:00Z"
    }

    issue =
      Normalizer.normalize_story(story,
        workspace_url: "https://www.tapd.cn/53000000/prong/stories/view",
        workflow: %{
          workitem_type_id: "1153070854001000001",
          raw_state_by_route_key: %{review: "review"}
        },
        state_phase_map: %{
          "planning" => "todo",
          "developing" => "in_progress",
          "resolved" => "done"
        }
      )

    assert issue.id == "123456"
    assert issue.identifier == "TAPD-123456"
    assert issue.title == "Implement TAPD adapter"
    assert issue.description == "Add runtime integration"
    assert issue.priority == 3
    assert issue.state == "developing"
    assert issue.lifecycle_phase == "in_progress"
    assert issue.workitem_type_id == "1153070854001000001"
    assert issue.url == "https://www.tapd.cn/53000000/prong/stories/view"
    assert issue.labels == ["backend", "integration"]
    assert issue.workflow[:raw_state_by_route_key][:review] == "review"

    assert issue.blocked_by == [
             %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
             %{id: "222", identifier: "TAPD-222", state: nil, lifecycle_phase: nil}
           ]

    assert issue.assigned_to_worker
    assert issue.created_at == ~U[2026-04-01 10:00:00Z]
    assert issue.updated_at == ~U[2026-04-02 12:30:00Z]
  end

  test "merges raw blockers with relation-derived blockers without duplicates" do
    story = %{
      "id" => "123456",
      "name" => "Implement TAPD adapter",
      "status" => "developing",
      "blocked_by" => [
        %{"id" => "111", "status" => "planning"}
      ]
    }

    issue =
      Normalizer.normalize_story(story,
        state_phase_map: %{
          "planning" => "todo",
          "resolved" => "done"
        },
        blocked_by: [
          %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
          %{id: "222", identifier: "TAPD-222", state: "resolved", lifecycle_phase: "done"}
        ]
      )

    assert issue.blocked_by == [
             %{id: "111", identifier: "TAPD-111", state: "planning", lifecycle_phase: "todo"},
             %{id: "222", identifier: "TAPD-222", state: "resolved", lifecycle_phase: "done"}
           ]
  end
end
