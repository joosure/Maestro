defmodule SymphonyElixir.Agent.Capabilities do
  @moduledoc """
  Agent runtime capability strings.
  """

  @behaviour SymphonyElixir.Capability.Source

  @turn_run "agent.turn.run"
  @session_stateful "agent.session.stateful"
  @events_streaming "agent.events.streaming"
  @usage_metrics "agent.usage.metrics"
  @tools_dynamic "agent.tools.dynamic"
  @runtime_remote_worker "agent.runtime.remote_worker"
  @credentials_managed "agent.credentials.managed"
  @quota_probe "agent.quota.probe"
  @execution_plan_snapshot "agent.execution_plan.snapshot"
  @execution_plan_upsert "agent.execution_plan.upsert"
  @execution_plan_update_item "agent.execution_plan.update_item"
  @execution_plan_append_evidence "agent.execution_plan.append_evidence"

  @spec turn_run() :: String.t()
  def turn_run, do: @turn_run

  @spec session_stateful() :: String.t()
  def session_stateful, do: @session_stateful

  @spec events_streaming() :: String.t()
  def events_streaming, do: @events_streaming

  @spec usage_metrics() :: String.t()
  def usage_metrics, do: @usage_metrics

  @spec tools_dynamic() :: String.t()
  def tools_dynamic, do: @tools_dynamic

  @spec runtime_remote_worker() :: String.t()
  def runtime_remote_worker, do: @runtime_remote_worker

  @spec credentials_managed() :: String.t()
  def credentials_managed, do: @credentials_managed

  @spec quota_probe() :: String.t()
  def quota_probe, do: @quota_probe

  @spec execution_plan_snapshot() :: String.t()
  def execution_plan_snapshot, do: @execution_plan_snapshot

  @spec execution_plan_upsert() :: String.t()
  def execution_plan_upsert, do: @execution_plan_upsert

  @spec execution_plan_update_item() :: String.t()
  def execution_plan_update_item, do: @execution_plan_update_item

  @spec execution_plan_append_evidence() :: String.t()
  def execution_plan_append_evidence, do: @execution_plan_append_evidence

  @impl true
  def capabilities do
    [
      turn_run(),
      session_stateful(),
      events_streaming(),
      usage_metrics(),
      tools_dynamic(),
      runtime_remote_worker(),
      credentials_managed(),
      quota_probe(),
      execution_plan_snapshot(),
      execution_plan_upsert(),
      execution_plan_update_item(),
      execution_plan_append_evidence()
    ]
  end

  @impl true
  def typed_tool_capabilities do
    [
      execution_plan_snapshot(),
      execution_plan_upsert(),
      execution_plan_update_item(),
      execution_plan_append_evidence()
    ]
  end
end
