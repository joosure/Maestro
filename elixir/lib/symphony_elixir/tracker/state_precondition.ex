defmodule SymphonyElixir.Tracker.StatePrecondition do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker.Error
  alias SymphonyElixir.Workflow.IssueContext

  @spec expected_current_state(keyword()) :: String.t() | nil
  def expected_current_state(opts) when is_list(opts) do
    opts
    |> Keyword.get(:expected_current_state)
    |> normalize_expected_value()
  end

  @spec check(String.t(), atom(), Issue.t(), String.t() | nil) :: :ok | {:error, Error.t()}
  def check(_provider, _operation, %Issue{}, nil), do: :ok

  def check(provider, operation, %Issue{} = issue, expected)
      when is_binary(provider) and is_atom(operation) and is_binary(expected) do
    if expected in current_state_values(issue) do
      :ok
    else
      {:error, state_conflict_error(provider, operation, issue, expected)}
    end
  end

  @spec issue_missing_error(String.t(), atom(), String.t(), String.t()) :: Error.t()
  def issue_missing_error(provider, operation, issue_id, expected)
      when is_binary(provider) and is_atom(operation) and is_binary(issue_id) and is_binary(expected) do
    Error.new(%{
      provider: provider,
      operation: operation,
      code: :not_found,
      message: "Tracker issue could not be read before conditional state update.",
      details: %{
        issue_id: issue_id,
        expected_current_state: expected,
        source_reason: :expected_current_state_issue_missing
      }
    })
  end

  defp state_conflict_error(provider, operation, %Issue{} = issue, expected) do
    Error.new(%{
      provider: provider,
      operation: operation,
      code: :state_conflict,
      message: "Tracker issue state changed before conditional state update.",
      details: %{
        issue_id: issue.id,
        expected_current_state: expected,
        actual_state: issue.state,
        actual_lifecycle_phase: issue.lifecycle_phase,
        current_state_values: current_state_values(issue),
        source_reason: :expected_current_state_mismatch
      }
    })
  end

  defp current_state_values(%Issue{} = issue) do
    ([issue.state, issue.lifecycle_phase] ++ route_keys_for_current_state(issue))
    |> Enum.flat_map(&string_value/1)
    |> Enum.uniq()
  end

  defp route_keys_for_current_state(%Issue{} = issue) do
    issue
    |> IssueContext.raw_state_by_route_key(%{})
    |> case do
      route_states when is_map(route_states) ->
        route_states
        |> Enum.filter(fn {_route_key, raw_state} -> string_value(raw_state) == string_value(issue.state) end)
        |> Enum.flat_map(fn {route_key, _raw_state} -> string_value(route_key) end)

      _route_states ->
        []
    end
  end

  defp normalize_expected_value(nil), do: nil

  defp normalize_expected_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_expected_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_expected_value(_value), do: nil

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp string_value(value) when is_atom(value), do: [Atom.to_string(value)]
  defp string_value(_value), do: []
end
