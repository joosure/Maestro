defmodule SymphonyElixir.Workflow.ChangeProposalReconciliation.Decision do
  @moduledoc false

  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.{Config, Facts}

  defstruct [:action, :reason, :target_route]

  @type action ::
          :noop
          | :move_to_route
          | :blocked
          | :provider_retry_later
          | :invalid_configuration

  @type t :: %__MODULE__{
          action: action(),
          reason: atom(),
          target_route: atom() | nil
        }

  @spec decide(Config.t(), term(), map(), Facts.t(), map()) :: t()
  def decide(config, route_facts, issue, facts, counters \\ %{})

  def decide(%Config{} = config, _route_facts, _issue, %Facts{} = facts, counters)
      when is_map(counters) do
    Enum.find_value(decision_rules(), fn rule ->
      rule.(config, facts, counters)
    end) || ready_decision(config)
  end

  def decide(_config, _route_facts, _issue, _facts, _counters), do: invalid_configuration(:invalid_decision_input)

  @spec noop(atom()) :: t()
  def noop(reason) when is_atom(reason), do: %__MODULE__{action: :noop, reason: reason}

  @spec move(atom(), atom()) :: t()
  def move(target_route, reason) when is_atom(target_route) and is_atom(reason) do
    %__MODULE__{action: :move_to_route, reason: reason, target_route: target_route}
  end

  @spec blocked(atom()) :: t()
  def blocked(reason) when is_atom(reason), do: %__MODULE__{action: :blocked, reason: reason}

  @spec provider_retry_later(atom()) :: t()
  def provider_retry_later(reason) when is_atom(reason) do
    %__MODULE__{action: :provider_retry_later, reason: reason}
  end

  @spec invalid_configuration(atom()) :: t()
  def invalid_configuration(reason) when is_atom(reason) do
    %__MODULE__{action: :invalid_configuration, reason: reason}
  end

  defp decision_rules do
    [
      &missing_change_proposal_rule/3,
      &provider_error_rule/3,
      &provider_state_rule/3,
      &feedback_rule/3,
      &review_rule/3,
      &check_rule/3,
      &mergeability_rule/3,
      &approval_gate_rule/3,
      &checks_gate_rule/3,
      &mergeability_gate_rule/3
    ]
  end

  defp missing_change_proposal_rule(_config, facts, _counters) do
    if missing_change_proposal?(facts), do: noop(:missing_change_proposal)
  end

  defp provider_error_rule(_config, facts, _counters) do
    cond do
      not is_nil(facts.error) and facts.retryable? -> provider_retry_later(:provider_retryable_error)
      not is_nil(facts.error) -> blocked(:provider_non_retryable_error)
      true -> nil
    end
  end

  defp provider_state_rule(config, facts, _counters) do
    case facts.provider_state do
      :unknown -> provider_retry_later(:provider_state_unknown)
      :merged -> move_or_noop(config.already_merged_target_route, :already_merged)
      :closed -> move_or_blocked(config.changes_requested_target_route, :closed_unmerged)
      _state -> nil
    end
  end

  defp feedback_rule(_config, facts, _counters) do
    if facts.unresolved_actionable_feedback?, do: noop(:unresolved_feedback)
  end

  defp review_rule(config, facts, _counters) do
    if facts.review_summary == :changes_requested do
      move_or_noop(config.changes_requested_target_route, :changes_requested)
    end
  end

  defp check_rule(config, facts, counters) do
    cond do
      facts.check_summary == :pending ->
        noop(:checks_pending)

      facts.check_summary == :absent and config.require_passing_checks? ->
        noop(:checks_absent)

      facts.check_summary == :failing and failed_check_count(counters) < config.failed_checks_confirmation_count ->
        noop(:checks_failing_unconfirmed)

      facts.check_summary == :failing ->
        move_or_noop(config.failed_checks_target_route, :checks_failing)

      true ->
        nil
    end
  end

  defp mergeability_rule(config, facts, _counters) do
    if facts.mergeability_summary == :conflicting do
      move_or_noop(config.failed_checks_target_route, :merge_conflict)
    end
  end

  defp approval_gate_rule(config, facts, _counters) do
    if config.require_approval? and facts.review_summary != :approved, do: noop(:approval_missing)
  end

  defp checks_gate_rule(config, facts, _counters) do
    if config.require_passing_checks? and facts.check_summary != :passing, do: noop(:checks_not_passing)
  end

  defp mergeability_gate_rule(config, facts, _counters) do
    if config.require_mergeable? and facts.mergeability_summary != :mergeable do
      noop(:mergeability_not_ready)
    end
  end

  defp ready_decision(%Config{ready_target_route: nil}), do: invalid_configuration(:missing_ready_target_route)
  defp ready_decision(%Config{ready_target_route: target_route}), do: move(target_route, :ready_to_land)

  defp missing_change_proposal?(%Facts{} = facts) do
    is_nil(facts.number) and is_nil(facts.url) and is_nil(facts.head_sha) and is_nil(facts.error)
  end

  defp move_or_noop(nil, reason), do: noop(reason)
  defp move_or_noop(target_route, reason), do: move(target_route, reason)

  defp move_or_blocked(nil, reason), do: blocked(reason)
  defp move_or_blocked(target_route, reason), do: move(target_route, reason)

  defp failed_check_count(%{failed_checks_count: count}) when is_integer(count) and count >= 0, do: count
  defp failed_check_count(%{"failed_checks_count" => count}) when is_integer(count) and count >= 0, do: count
  defp failed_check_count(_counters), do: 0
end
