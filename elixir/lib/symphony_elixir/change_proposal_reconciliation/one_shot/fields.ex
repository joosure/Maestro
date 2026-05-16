defmodule SymphonyElixir.ChangeProposalReconciliation.OneShot.Fields do
  @moduledoc false

  @summary_fields [
    "event",
    "level",
    "status",
    "candidate_fetch_mode",
    "processed_count",
    "candidate_count",
    "decision",
    "reason",
    "source_route",
    "source_state",
    "target_route",
    "target_state",
    "skip_reason",
    "change_proposal_number",
    "change_proposal_url",
    "provider_state",
    "review_summary",
    "check_summary",
    "mergeability_summary",
    "error"
  ]

  @spec event() :: String.t()
  def event, do: "event"

  @spec decision() :: String.t()
  def decision, do: "decision"

  @spec reason() :: String.t()
  def reason, do: "reason"

  @spec target_route() :: String.t()
  def target_route, do: "target_route"

  @spec target_state() :: String.t()
  def target_state, do: "target_state"

  @spec skip_reason() :: String.t()
  def skip_reason, do: "skip_reason"

  @spec summary_fields() :: [String.t()]
  def summary_fields, do: @summary_fields
end
