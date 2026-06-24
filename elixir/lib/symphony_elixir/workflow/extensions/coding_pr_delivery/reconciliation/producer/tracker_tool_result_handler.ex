defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.AttachTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.ReviewTransitionTarget
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Router

  @spec record(map(), String.t() | nil, term(), term(), keyword()) :: :ok
  def record(tracker, tool, arguments, result, opts \\ [])

  def record(tracker, tool, arguments, {:success, payload}, opts)
      when is_map(tracker) and is_binary(tool) do
    if Keyword.keyword?(opts) do
      dispatch(tracker, tool, arguments, payload, opts)
    else
      Events.invalid_options(tracker, tool, opts)
    end
  end

  def record(_tracker, _tool, _arguments, _result, _opts), do: :ok

  defp dispatch(tracker, tool, arguments, payload, opts) do
    attach_capability = Contract.tracker_attach_external_reference_capability()
    move_capability = Contract.tracker_move_issue_capability()

    case Router.capability(tracker, tool, opts) do
      ^attach_capability ->
        AttachTarget.record(tracker, tool, arguments, payload, opts)

      ^move_capability ->
        ReviewTransitionTarget.record(tracker, tool, arguments, payload, opts)

      nil ->
        Events.ignored(tracker, tool, arguments, :missing_workflow_capability, %{}, opts)

      _other_capability ->
        :ok
    end
  end
end
