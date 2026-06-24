defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceContract do
  @moduledoc """
  Normalized evidence payload keys consumed by structured execution-plan reconciliation.

  This contract is intentionally local to structured execution plans. It avoids
  coupling plan evidence policies to transition-readiness policy vocabulary.
  """

  @status_key "status"
  @url_key "url"
  @head_sha_key "head_sha"
  @published_head_sha_key "published_head_sha"
  @linked_to_tracker_key "linked_to_tracker"

  @spec status_key() :: String.t()
  def status_key, do: @status_key

  @spec url_key() :: String.t()
  def url_key, do: @url_key

  @spec head_sha_key() :: String.t()
  def head_sha_key, do: @head_sha_key

  @spec published_head_sha_key() :: String.t()
  def published_head_sha_key, do: @published_head_sha_key

  @spec linked_to_tracker_key() :: String.t()
  def linked_to_tracker_key, do: @linked_to_tracker_key
end
