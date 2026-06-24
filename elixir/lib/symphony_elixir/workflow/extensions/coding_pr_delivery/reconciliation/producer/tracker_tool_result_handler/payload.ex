defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Payload do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values

  @external_reference_id_key "id"
  @external_reference_url_key "url"
  @issue_identifier_key "identifier"
  @issue_key "issue"
  @issue_id_key "id"
  @issue_state_key "state"
  @issue_workflow_key "workflow"
  @state_id_key "id"
  @state_name_key "name"
  @state_type_key "type"

  @spec external_reference_id(map()) :: String.t() | nil
  def external_reference_id(external_reference), do: Values.string_value(external_reference, @external_reference_id_key)

  @spec external_reference_url(map()) :: String.t() | nil
  def external_reference_url(external_reference), do: Values.string_value(external_reference, @external_reference_url_key)

  @spec issue(term()) :: Issue.t() | nil
  def issue(payload) do
    case payload_issue(payload) do
      %Issue{} = issue ->
        issue

      issue when is_map(issue) ->
        %Issue{
          id: Values.string_value(issue, @issue_id_key),
          identifier: Values.string_value(issue, @issue_identifier_key),
          state: issue_state(issue),
          lifecycle_phase: issue_lifecycle_phase(issue),
          workflow: Values.map_value(issue, @issue_workflow_key) || %{}
        }

      _issue ->
        nil
    end
  end

  @spec issue_id(term()) :: String.t() | nil
  def issue_id(payload) do
    payload
    |> payload_issue()
    |> case do
      %Issue{id: issue_id} when is_binary(issue_id) -> issue_id
      issue when is_map(issue) -> Values.string_value(issue, @issue_id_key)
      _issue -> nil
    end
  end

  defp payload_issue(%{@issue_key => issue}), do: issue
  defp payload_issue(_payload), do: nil

  defp issue_state(issue) when is_map(issue) do
    case Values.map_value(issue, @issue_state_key) do
      state when is_map(state) -> Values.string_value(state, @state_id_key) || Values.string_value(state, @state_name_key)
      state when is_binary(state) -> state
      _state -> nil
    end
  end

  defp issue_lifecycle_phase(issue) when is_map(issue) do
    case Values.map_value(issue, @issue_state_key) do
      state when is_map(state) -> Values.string_value(state, @state_type_key)
      _state -> nil
    end
  end
end
