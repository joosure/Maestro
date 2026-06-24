defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Producers do
  @moduledoc false

  @component "change_proposal_reconciliation"
  @tracker_tool_result_producer "tracker_tool_result"
  @known_target_watcher_producer "known_target_watcher"
  @known_target_registry_producer "known_target_registry"
  @startup_backlog_bootstrap_producer "startup_backlog_bootstrap"

  @type producer_id ::
          :tracker_tool_result
          | :known_target_watcher
          | :known_target_registry
          | :startup_backlog_bootstrap

  @spec component() :: String.t()
  def component, do: @component

  @spec producer(producer_id()) :: String.t()
  def producer(:tracker_tool_result), do: @tracker_tool_result_producer
  def producer(:known_target_watcher), do: @known_target_watcher_producer
  def producer(:known_target_registry), do: @known_target_registry_producer
  def producer(:startup_backlog_bootstrap), do: @startup_backlog_bootstrap_producer
end
