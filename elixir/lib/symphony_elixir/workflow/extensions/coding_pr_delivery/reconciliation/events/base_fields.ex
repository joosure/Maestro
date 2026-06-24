defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.BaseFields do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.EventBaseFieldDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput

  @spec merge(map(), Issue.t() | nil, RuntimeInput.t(), map()) :: map()
  def merge(settings, issue, state, fields) when is_map(settings) and is_map(fields) do
    fields
    |> Map.put_new(Fields.repo_provider_kind(), EventBaseFieldDefaults.repo_provider_kind(settings))
    |> Map.merge(profile_fields(settings))
    |> event_fields(settings, issue, state)
  end

  defp event_fields(fields, settings, issue, state) when is_map(fields) do
    %{
      Fields.component() => Contract.component(),
      Fields.tracker_kind() => tracker_kind(settings),
      Fields.issue_id() => issue_id(issue),
      Fields.issue_identifier() => issue_identifier(issue),
      Fields.running_count() => running_count(state),
      Fields.claimed_count() => claimed_count(state),
      Fields.available_slots() => available_slots_for_event(state),
      Fields.max_concurrent_agents() => max_concurrent_agents_for_event(state)
    }
    |> Map.merge(fields)
  end

  defp tracker_kind(settings), do: EventBaseFieldDefaults.tracker_kind(settings)

  defp profile_fields(settings) do
    case EventBaseFieldDefaults.profile_context(settings) do
      {:ok, profile_context} ->
        %{
          Fields.workflow_profile_kind() => profile_context.kind,
          Fields.workflow_profile_version() => profile_context.version
        }

      {:error, _reason} ->
        %{}
    end
  end

  defp issue_id(%Issue{id: issue_id}), do: issue_id
  defp issue_id(_issue), do: nil

  defp issue_identifier(%Issue{identifier: identifier}), do: identifier
  defp issue_identifier(_issue), do: nil

  defp running_count(%RuntimeInput{running_count: count}) when is_integer(count), do: count
  defp running_count(_state), do: nil

  defp claimed_count(%RuntimeInput{claimed_count: count}) when is_integer(count), do: count
  defp claimed_count(_state), do: nil

  defp available_slots_for_event(%RuntimeInput{available_slots: available_slots}), do: available_slots

  defp available_slots_for_event(_state), do: nil

  defp max_concurrent_agents_for_event(%RuntimeInput{max_concurrent_agents: max}), do: max
  defp max_concurrent_agents_for_event(_state), do: nil
end
