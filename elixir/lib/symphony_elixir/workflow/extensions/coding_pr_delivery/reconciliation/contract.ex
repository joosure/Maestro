defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Capabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Events
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Producers
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Reasons
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Statuses

  @type event_id :: Events.event_id()
  @type producer_id :: Producers.producer_id()
  @type reconciliation_status :: Statuses.reconciliation_status()
  @type producer_status :: Statuses.producer_status()

  @spec component() :: String.t()
  def component, do: Producers.component()

  @spec producer(producer_id()) :: String.t()
  def producer(producer_id), do: Producers.producer(producer_id)

  @spec tracker_attach_external_reference_capability() :: String.t()
  def tracker_attach_external_reference_capability, do: Capabilities.tracker_attach_external_reference_capability()

  @spec tracker_move_issue_capability() :: String.t()
  def tracker_move_issue_capability, do: Capabilities.tracker_move_issue_capability()

  @spec event(event_id()) :: atom()
  def event(event_id), do: Events.event(event_id)

  @spec event_name(event_id()) :: String.t()
  def event_name(event_id), do: Events.event_name(event_id)

  @spec transition_events() :: [String.t()]
  def transition_events, do: Events.transition_events()

  @spec transition_event_name(:attempted | :failed | :skipped | :succeeded) :: String.t()
  def transition_event_name(transition_status), do: Events.transition_event_name(transition_status)

  @spec reconciliation_status(reconciliation_status()) :: String.t()
  def reconciliation_status(status), do: Statuses.reconciliation_status(status)

  @spec producer_status(producer_status()) :: String.t()
  def producer_status(status), do: Statuses.producer_status(status)

  @spec reason_name(atom() | String.t()) :: String.t()
  def reason_name(reason), do: Reasons.reason_name(reason)
end
