defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Lifecycle do
  @moduledoc """
  Lifecycle state for runtime-targeted reconciliation candidates.

  This module owns defer/suspend/reactivate policy. The inbox owns queue order
  and process boundaries; producers and reconcilers only supply candidate ids
  and defer reasons.
  """

  @default_max_defer_count 20
  @default_max_defer_age_ms 30 * 60 * 1_000

  defstruct deferred: %{},
            suspended: %{},
            max_defer_count: @default_max_defer_count,
            max_defer_age_ms: @default_max_defer_age_ms

  @type t :: %__MODULE__{
          deferred: map(),
          suspended: map(),
          max_defer_count: pos_integer(),
          max_defer_age_ms: pos_integer()
        }

  @type defer_policy :: %{
          required(:now_ms) => integer(),
          optional(:reason) => atom() | String.t() | nil,
          optional(:route) => atom() | String.t() | nil,
          optional(:max_defer_count) => pos_integer() | nil,
          optional(:max_defer_age_ms) => pos_integer() | nil
        }

  @type defer_result :: %{
          required(:lifecycle) => t(),
          required(:deferred_issue_ids) => [String.t()],
          required(:suspended_issue_ids) => [String.t()]
        }

  @spec new(keyword()) :: t()
  def new(opts \\ [])

  def new(opts) when is_list(opts) do
    unless Keyword.keyword?(opts), do: raise(ArgumentError, "candidate lifecycle options must be a keyword list")

    %__MODULE__{
      max_defer_count: non_negative_integer!(Keyword.get(opts, :max_defer_count, @default_max_defer_count), :max_defer_count),
      max_defer_age_ms: non_negative_integer!(Keyword.get(opts, :max_defer_age_ms, @default_max_defer_age_ms), :max_defer_age_ms)
    }
  end

  def new(_opts), do: raise(ArgumentError, "candidate lifecycle options must be a keyword list")

  @spec defer(t(), [String.t()], defer_policy()) :: defer_result()
  def defer(%__MODULE__{} = lifecycle, issue_ids, policy)
      when is_list(issue_ids) and is_map(policy) do
    now_ms = Map.fetch!(policy, :now_ms)

    {lifecycle, deferred_issue_ids, suspended_issue_ids} =
      Enum.reduce(issue_ids, {lifecycle, [], []}, fn issue_id, {%__MODULE__{} = lifecycle_acc, deferred_ids, suspended_ids} ->
        defer_entry = next_defer_entry(lifecycle_acc, issue_id, policy)

        if suspend_defer?(lifecycle_acc, defer_entry, policy) do
          lifecycle_acc = suspend_issue(lifecycle_acc, issue_id, defer_entry, now_ms)
          {lifecycle_acc, deferred_ids, [issue_id | suspended_ids]}
        else
          lifecycle_acc = put_deferred(lifecycle_acc, issue_id, defer_entry)
          {lifecycle_acc, [issue_id | deferred_ids], suspended_ids}
        end
      end)

    %{
      lifecycle: lifecycle,
      deferred_issue_ids: Enum.reverse(deferred_issue_ids),
      suspended_issue_ids: Enum.reverse(suspended_issue_ids)
    }
  end

  @spec reactivate(t(), [String.t()]) :: {t(), non_neg_integer()}
  def reactivate(%__MODULE__{} = lifecycle, issue_ids) when is_list(issue_ids) do
    reactivated_ids =
      Enum.filter(issue_ids, fn issue_id ->
        Map.has_key?(lifecycle.deferred, issue_id) or Map.has_key?(lifecycle.suspended, issue_id)
      end)

    lifecycle = %{
      lifecycle
      | deferred: Map.drop(lifecycle.deferred, reactivated_ids),
        suspended: Map.drop(lifecycle.suspended, reactivated_ids)
    }

    {lifecycle, length(reactivated_ids)}
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = lifecycle), do: %{lifecycle | deferred: %{}, suspended: %{}}

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = lifecycle) do
    %{
      deferred_count: map_size(lifecycle.deferred),
      suspended_count: map_size(lifecycle.suspended),
      deferred: lifecycle.deferred,
      suspended: lifecycle.suspended,
      policy: %{
        max_defer_count: lifecycle.max_defer_count,
        max_defer_age_ms: lifecycle.max_defer_age_ms
      }
    }
  end

  defp next_defer_entry(%__MODULE__{} = lifecycle, issue_id, policy) do
    now_ms = Map.fetch!(policy, :now_ms)
    existing = Map.get(lifecycle.deferred, issue_id) || Map.get(lifecycle.suspended, issue_id) || %{}
    first_deferred_at_ms = Map.get(existing, :first_deferred_at_ms) || now_ms

    %{
      first_deferred_at_ms: first_deferred_at_ms,
      last_deferred_at_ms: now_ms,
      deferred_count: Map.get(existing, :deferred_count, 0) + 1,
      last_deferred_route: Map.get(policy, :route),
      defer_reason: Map.get(policy, :reason)
    }
  end

  defp suspend_defer?(%__MODULE__{} = lifecycle, entry, policy) when is_map(entry) do
    max_defer_count = Map.get(policy, :max_defer_count) || lifecycle.max_defer_count
    max_defer_age_ms = Map.get(policy, :max_defer_age_ms) || lifecycle.max_defer_age_ms

    entry.deferred_count > max_defer_count or
      entry.last_deferred_at_ms - entry.first_deferred_at_ms >= max_defer_age_ms
  end

  defp put_deferred(%__MODULE__{} = lifecycle, issue_id, entry) do
    %{
      lifecycle
      | deferred: Map.put(lifecycle.deferred, issue_id, entry),
        suspended: Map.delete(lifecycle.suspended, issue_id)
    }
  end

  defp suspend_issue(%__MODULE__{} = lifecycle, issue_id, entry, now_ms) do
    suspended_entry =
      entry
      |> Map.put(:suspended_at_ms, now_ms)
      |> Map.put(:suspend_reason, :defer_policy_exceeded)

    %{
      lifecycle
      | deferred: Map.delete(lifecycle.deferred, issue_id),
        suspended: Map.put(lifecycle.suspended, issue_id, suspended_entry)
    }
  end

  defp non_negative_integer!(value, _key) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer!(_value, key), do: raise(ArgumentError, "invalid candidate lifecycle #{key}")
end
