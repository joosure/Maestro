defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding.CheckStatus.Contract do
  @moduledoc """
  External provider checks payload contract.

  These keys and bucket aliases belong to the typed-tool/provider checks
  boundary. They are normalized by `CheckStatus` before workflow readiness code
  consumes stable readiness statuses.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values, as: ReadinessValues

  @runs_key "runs"
  @summary_key "summary"
  @bucket_key "bucket"
  @state_key "state"

  @failed_buckets [ReadinessValues.failed_status(), "failure", "error", "cancelled", "canceled", "timed_out", "timedout", "red"]
  @pending_buckets [ReadinessValues.pending_status(), "queued", "running", "in_progress", "waiting", "yellow"]
  @passed_buckets [ReadinessValues.passed_status(), "success", "successful", "green", "neutral", "skipped"]

  @spec runs_key() :: String.t()
  def runs_key, do: @runs_key

  @spec summary_key() :: String.t()
  def summary_key, do: @summary_key

  @spec bucket_key() :: String.t()
  def bucket_key, do: @bucket_key

  @spec state_key() :: String.t()
  def state_key, do: @state_key

  @spec failed_buckets() :: [String.t()]
  def failed_buckets, do: @failed_buckets

  @spec pending_buckets() :: [String.t()]
  def pending_buckets, do: @pending_buckets

  @spec passed_buckets() :: [String.t()]
  def passed_buckets, do: @passed_buckets
end
