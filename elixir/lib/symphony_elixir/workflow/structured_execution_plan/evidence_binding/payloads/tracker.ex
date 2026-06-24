defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.Payloads.Tracker do
  @moduledoc """
  Normalizes tracker typed-tool results into evidence payloads.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.ToolMap

  @tracker_upsert_workpad ToolMap.tracker_upsert_workpad_evidence_kind()
  @tracker_move_issue ToolMap.tracker_move_issue_evidence_kind()

  @spec normalize(String.t(), String.t() | atom() | nil, term(), term(), map()) :: {:ok, map()}
  def normalize(@tracker_upsert_workpad, source_kind, _source_context, _arguments, payload) do
    comment = get_in(payload, ["data", "comment"]) || %{}

    {:ok,
     RawInput.compact(%{
       "tracker_kind" => source_kind && to_string(source_kind),
       "workpad_id" => RawInput.string_value(comment, "id"),
       "created" => Map.get(comment, "created"),
       "updated" => Map.get(comment, "updated")
     })}
  end

  def normalize(@tracker_move_issue, source_kind, _source_context, arguments, payload) do
    issue = get_in(payload, ["data", "issue"]) || %{}
    state = Map.get(issue, "state", %{}) || %{}

    {:ok,
     RawInput.compact(%{
       "tracker_kind" => source_kind && to_string(source_kind),
       "issue_id" => RawInput.string_value(issue, "id") || RawInput.string_value(arguments, "issue_id"),
       "state_name" => RawInput.string_value(state, "name") || RawInput.string_value(arguments, "state_name"),
       "state_id" => RawInput.string_value(state, "id"),
       "route_key" => RawInput.string_value(arguments, "route_key"),
       "lifecycle_phase" => RawInput.string_value(arguments, "lifecycle_phase")
     })}
  end

  def normalize(_evidence_kind, _source_kind, _source_context, _arguments, _payload), do: {:ok, %{}}
end
