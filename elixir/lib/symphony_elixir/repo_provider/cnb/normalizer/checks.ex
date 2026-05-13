defmodule SymphonyElixir.RepoProvider.CNB.Normalizer.Checks do
  @moduledoc false

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
                overall_state in [
                  "success",
                  "passed",
                  "failure",
                  "failed",
                  "error",
                  "cancelled",
                  "timed_out",
                  "action_required"
                ],
                do: "completed",
                else: "in_progress"
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

    pending = state in ["pending", "queued", "created", "running", "in_progress", "checking", ""]

    %{
      "name" => Map.get(status, "context", status[:context] || "unknown"),
      "status" => if(pending, do: "in_progress", else: "completed"),
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
      normalized in ["success", "passed"] ->
        "success"

      normalized == "neutral" ->
        "neutral"

      normalized == "skipped" ->
        "skipped"

      normalized in ["pending", "queued", "created", "running", "in_progress", "checking", ""] ->
        "pending"

      normalized == "error" ->
        "error"

      normalized == "cancelled" ->
        "cancelled"

      true ->
        "failure"
    end
  end
end
