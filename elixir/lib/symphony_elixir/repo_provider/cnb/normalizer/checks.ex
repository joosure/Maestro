defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Checks do
  @moduledoc false

  @status_completed "completed"
  @status_in_progress "in_progress"
  @conclusion_pending "pending"
  @conclusion_success "success"
  @conclusion_neutral "neutral"
  @conclusion_skipped "skipped"
  @conclusion_error "error"
  @conclusion_cancelled "cancelled"
  @conclusion_failure "failure"

  @overall_completed_states ["success", "passed", "failure", "failed", "error", "cancelled", "timed_out", "action_required"]
  @pending_states ["pending", "queued", "created", "running", "in_progress", "checking", ""]
  @check_conclusion_by_state %{
    "success" => @conclusion_success,
    "passed" => @conclusion_success,
    "neutral" => @conclusion_neutral,
    "skipped" => @conclusion_skipped,
    "error" => @conclusion_error,
    "cancelled" => @conclusion_cancelled
  }

  @spec normalize_check_payload(map()) :: list(map())
  def normalize_check_payload(payload) when is_map(payload) do
    check_runs =
      payload
      |> Map.get("statuses", payload[:statuses] || [])
      |> case do
        statuses when is_list(statuses) ->
          Enum.flat_map(statuses, fn
            status when is_map(status) -> [normalize_check_run(status)]
            _status -> []
          end)

        _other ->
          []
      end

    if check_runs == [] do
      overall_state =
        payload
        |> Map.get("state", payload[:state] || "")
        |> to_string()
        |> String.trim()
        |> String.downcase()

      if overall_state == "" do
        []
      else
        [
          %{
            "name" => "overall",
            "status" =>
              if(
                overall_state in @overall_completed_states,
                do: @status_completed,
                else: @status_in_progress
              ),
            "conclusion" => map_check_conclusion(overall_state),
            "created_at" => nil,
            "started_at" => nil,
            "completed_at" => nil,
            "details_url" => nil,
            "summary" => overall_state
          }
        ]
      end
    else
      check_runs
    end
  end

  @spec normalize_check_run(map()) :: map()
  def normalize_check_run(status) when is_map(status) do
    state =
      status
      |> Map.get("state", status[:state] || "")
      |> to_string()
      |> String.downcase()

    pending = state in @pending_states

    %{
      "name" => Map.get(status, "context", status[:context] || "unknown"),
      "status" => if(pending, do: @status_in_progress, else: @status_completed),
      "conclusion" => if(pending, do: nil, else: map_check_conclusion(state)),
      "created_at" => Map.get(status, "created_at", status[:created_at]),
      "started_at" => Map.get(status, "created_at", status[:created_at]),
      "completed_at" => Map.get(status, "updated_at", status[:updated_at]),
      "details_url" => Map.get(status, "target_url", status[:target_url]),
      "summary" => Map.get(status, "description", status[:description])
    }
  end

  @spec map_check_conclusion(String.t()) :: String.t()
  def map_check_conclusion(state) when is_binary(state) do
    normalized = String.downcase(state)

    cond do
      normalized in @pending_states ->
        @conclusion_pending

      true ->
        Map.get(@check_conclusion_by_state, normalized, @conclusion_failure)
    end
  end
end
