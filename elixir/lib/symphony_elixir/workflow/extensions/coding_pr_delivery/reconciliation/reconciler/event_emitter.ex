defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.EventEmitter do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Fields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Clients
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Options
  alias SymphonyElixir.Workflow.RouteRef

  @spec candidate_suspended(term(), [String.t()], map(), Options.t()) :: :ok
  def candidate_suspended({:ok, result}, issue_ids, details, %Options{} = options)
      when is_map(result) and is_list(issue_ids) and is_map(details) do
    suspended_issue_ids = Map.get(result, :suspended_issue_ids, [])

    if Map.get(result, :suspended_count, 0) > 0 and suspended_issue_ids != [] do
      Enum.each(suspended_issue_ids, fn issue_id ->
        _result =
          Clients.emit_event(
            :info,
            Contract.event(:candidate_suspended),
            %{
              Fields.component() => Contract.component(),
              Fields.issue_id() => issue_id,
              Fields.reason() => Contract.reason_name(Map.get(details, :reason, :defer_policy_exceeded)),
              Fields.source_workflow_profile() => route_ref_value(details, :profile_kind),
              Fields.source_workflow_profile_version() => route_ref_value(details, :profile_version),
              Fields.source_workflow_route_key() => route_ref_value(details, :route_key),
              requested_issue_count: length(issue_ids),
              suspended_count: Map.get(result, :suspended_count)
            },
            options
          )
      end)
    end

    :ok
  end

  def candidate_suspended(_result, _issue_ids, _details, %Options{}), do: :ok

  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :profile_kind), do: route_ref.profile_kind
  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :profile_version), do: route_ref.profile_version
  defp route_ref_value(%{route_ref: %RouteRef{} = route_ref}, :route_key), do: Atom.to_string(route_ref.route_key)
  defp route_ref_value(_details, _field), do: nil
end
