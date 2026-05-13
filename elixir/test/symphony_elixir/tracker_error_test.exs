defmodule SymphonyElixir.TrackerErrorTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Tracker.Error, as: TrackerError

  test "normalizes linear HTTP failures into retryable tracker errors" do
    error =
      TrackerError.new(%{
        provider: "linear",
        operation: :fetch_issue_states_by_ids,
        code: :http_status,
        retryable?: true,
        details: %{status: 503}
      })

    assert %TrackerError{
             provider: "linear",
             operation: :fetch_issue_states_by_ids,
             code: :http_status,
             retryable?: true,
             details: %{status: 503}
           } = error

    assert TrackerError.retryable?(error)
  end

  test "normalizes nested tapd workflow lookup failures and preserves nested retryability" do
    error =
      TrackerError.new(%{
        provider: "tapd",
        operation: :fetch_issue_states_by_ids,
        code: :workflow_lookup_failed,
        retryable?: true,
        details: %{
          workitem_type_id: "story",
          workflow_type: "step",
          nested_error:
            TrackerError.new(%{
              provider: "tapd",
              operation: :fetch_issue_states_by_ids,
              code: :http_status,
              retryable?: true,
              details: %{status: 429}
            })
        }
      })

    assert %TrackerError{
             provider: "tapd",
             operation: :fetch_issue_states_by_ids,
             code: :workflow_lookup_failed,
             retryable?: true,
             details: %{
               workitem_type_id: "story",
               workflow_type: "step",
               nested_error: %TrackerError{code: :http_status, retryable?: true}
             }
           } = error
  end

  test "normalizes unsupported capability errors using tracker context" do
    tracker = %{kind: "fake_core"}

    error = TrackerError.normalize(tracker, :create_comment, :unsupported_tracker_write_capability)

    assert %TrackerError{
             provider: "fake_core",
             operation: :create_comment,
             code: :unsupported_capability,
             retryable?: false,
             details: %{capability: :writer}
           } = error
  end

  test "passes through normalized tracker errors while backfilling provider and operation" do
    error =
      TrackerError.new(%{
        provider: "unknown",
        operation: nil,
        code: :request_failed,
        retryable?: true
      })

    normalized = TrackerError.normalize(%{kind: "tapd"}, :fetch_candidate_issues, error)

    assert %TrackerError{
             provider: "tapd",
             operation: :fetch_candidate_issues,
             code: :request_failed,
             retryable?: true
           } = normalized
  end
end
