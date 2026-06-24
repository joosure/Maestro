defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.ProviderFacts.Contract do
  @moduledoc false

  @number_key "number"
  @url_key "url"
  @head_ref_name_key "headRefName"
  @head_ref_oid_key "headRefOid"
  @merged_key "merged"
  @merged_at_key "mergedAt"
  @state_key "state"
  @mergeable_key "mergeable"
  @merge_state_status_key "mergeStateStatus"
  @user_key "user"
  @submitted_at_key "submitted_at"
  @created_at_key "created_at"
  @updated_at_key "updated_at"
  @completed_at_key "completed_at"
  @started_at_key "started_at"
  @run_started_at_key "run_started_at"
  @body_key "body"
  @type_key "type"
  @in_reply_to_id_key "in_reply_to_id"
  @pull_request_review_id_key "pull_request_review_id"
  @id_key "id"
  @login_key "login"

  @provider_state_merged "merged"
  @provider_state_open "open"
  @provider_state_closed "closed"

  @review_state_changes_requested "changes_requested"
  @review_state_approved "approved"

  @mergeability_conflicting "conflicting"
  @mergeability_dirty "dirty"
  @mergeability_blocked "blocked"
  @mergeability_draft "draft"
  @mergeability_mergeable "mergeable"
  @mergeability_clean "clean"
  @mergeability_has_hooks "has_hooks"
  @mergeability_unstable "unstable"
  @mergeability_unknown "unknown"
  @mergeability_empty ""

  @utc_suffix "Z"
  @utc_offset "+00:00"

  @spec payload_key(atom()) :: String.t()
  def payload_key(:number), do: @number_key
  def payload_key(:url), do: @url_key
  def payload_key(:head_ref_name), do: @head_ref_name_key
  def payload_key(:head_ref_oid), do: @head_ref_oid_key
  def payload_key(:merged), do: @merged_key
  def payload_key(:merged_at), do: @merged_at_key
  def payload_key(:state), do: @state_key
  def payload_key(:mergeable), do: @mergeable_key
  def payload_key(:merge_state_status), do: @merge_state_status_key
  def payload_key(:user), do: @user_key
  def payload_key(:submitted_at), do: @submitted_at_key
  def payload_key(:created_at), do: @created_at_key
  def payload_key(:updated_at), do: @updated_at_key
  def payload_key(:completed_at), do: @completed_at_key
  def payload_key(:started_at), do: @started_at_key
  def payload_key(:run_started_at), do: @run_started_at_key
  def payload_key(:body), do: @body_key
  def payload_key(:type), do: @type_key
  def payload_key(:in_reply_to_id), do: @in_reply_to_id_key
  def payload_key(:pull_request_review_id), do: @pull_request_review_id_key
  def payload_key(:id), do: @id_key
  def payload_key(:login), do: @login_key

  @spec provider_state_by_name() :: %{String.t() => :closed | :merged | :open}
  def provider_state_by_name do
    %{
      @provider_state_merged => :merged,
      @provider_state_open => :open,
      @provider_state_closed => :closed
    }
  end

  @spec review_state(atom()) :: String.t()
  def review_state(:changes_requested), do: @review_state_changes_requested
  def review_state(:approved), do: @review_state_approved

  @spec mergeability(atom()) :: String.t()
  def mergeability(:conflicting), do: @mergeability_conflicting
  def mergeability(:dirty), do: @mergeability_dirty
  def mergeability(:blocked), do: @mergeability_blocked
  def mergeability(:draft), do: @mergeability_draft
  def mergeability(:mergeable), do: @mergeability_mergeable
  def mergeability(:clean), do: @mergeability_clean
  def mergeability(:has_hooks), do: @mergeability_has_hooks
  def mergeability(:unstable), do: @mergeability_unstable
  def mergeability(:unknown), do: @mergeability_unknown
  def mergeability(:empty), do: @mergeability_empty

  @spec blocked_merge_states() :: [String.t()]
  def blocked_merge_states, do: [@mergeability_blocked, @mergeability_draft]

  @spec mergeable_merge_states() :: [String.t()]
  def mergeable_merge_states, do: [@mergeability_empty, @mergeability_clean, @mergeability_has_hooks, @mergeability_unstable, @mergeability_unknown]

  @spec fallback_mergeable_merge_states() :: [String.t()]
  def fallback_mergeable_merge_states, do: [@mergeability_clean, @mergeability_has_hooks, @mergeability_unstable]

  @spec utc_suffix() :: String.t()
  def utc_suffix, do: @utc_suffix

  @spec utc_offset() :: String.t()
  def utc_offset, do: @utc_offset
end
