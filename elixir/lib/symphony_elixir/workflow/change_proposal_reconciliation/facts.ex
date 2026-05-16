defmodule SymphonyElixir.Workflow.ChangeProposalReconciliation.Facts do
  @moduledoc false

  defstruct provider_kind: nil,
            repository: nil,
            number: nil,
            url: nil,
            branch: nil,
            head_sha: nil,
            provider_state: :unknown,
            review_summary: :unknown,
            check_summary: :unknown,
            mergeability_summary: :unknown,
            unresolved_actionable_feedback?: false,
            error: nil,
            retryable?: false,
            observed_at: nil

  @type provider_state :: :open | :closed | :merged | :unknown
  @type review_summary :: :approved | :changes_requested | :pending | :blocked | :unknown
  @type check_summary :: :passing | :failing | :pending | :absent | :unknown
  @type mergeability_summary :: :mergeable | :conflicting | :blocked | :unknown

  @type t :: %__MODULE__{
          provider_kind: String.t() | nil,
          repository: String.t() | nil,
          number: integer() | String.t() | nil,
          url: String.t() | nil,
          branch: String.t() | nil,
          head_sha: String.t() | nil,
          provider_state: provider_state(),
          review_summary: review_summary(),
          check_summary: check_summary(),
          mergeability_summary: mergeability_summary(),
          unresolved_actionable_feedback?: boolean(),
          error: term(),
          retryable?: boolean(),
          observed_at: DateTime.t() | nil
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)
end
