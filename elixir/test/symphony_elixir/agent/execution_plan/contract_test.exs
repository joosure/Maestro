defmodule SymphonyElixir.Agent.ExecutionPlan.ContractTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Contract

  @criticality_runtime_files [
    "lib/symphony_elixir/agent/execution_plan/schema.ex",
    "lib/symphony_elixir/agent/execution_plan/store/guards.ex",
    "lib/symphony_elixir/agent/execution_plan/tool_executor.ex"
  ]

  @agent_editable_item_runtime_files [
    "lib/symphony_elixir/agent/execution_plan/store.ex",
    "lib/symphony_elixir/agent/execution_plan/store/guards.ex",
    "lib/symphony_elixir/agent/execution_plan/tool_executor.ex"
  ]

  test "evidence-required criticalities are owned by the Agent execution plan contract" do
    assert Contract.evidence_required_criticalities() == ["critical", "policy_required"]
    assert Enum.all?(Contract.evidence_required_criticalities(), &Contract.criticality?/1)

    assert Contract.evidence_required_criticality?("critical")
    assert Contract.evidence_required_criticality?("policy_required")
    refute Contract.evidence_required_criticality?("task_required")
    refute Contract.evidence_required_criticality?("informational")
  end

  test "status transitions are owned by the Agent execution plan contract" do
    assert Contract.plan_status_transitions()["active"] == ["blocked", "closed", "superseded"]
    assert Contract.item_status_transitions()["pending"] == ["in_progress", "complete", "blocked", "skipped"]

    assert Map.keys(Contract.plan_status_transitions()) |> Enum.sort() == Enum.sort(Contract.plan_statuses())
    assert Map.keys(Contract.item_status_transitions()) |> Enum.sort() == Enum.sort(Contract.item_statuses())

    assert transition_targets(Contract.plan_status_transitions()) |> Enum.all?(&Contract.plan_status?/1)
    assert transition_targets(Contract.item_status_transitions()) |> Enum.all?(&Contract.item_status?/1)
  end

  test "agent-editable item policy values are owned by the Agent execution plan contract" do
    assert Contract.agent_owner() == "agent"
    assert Contract.agent_draft_source() == "agent_draft"
    assert Contract.informational_criticality() == "informational"
    assert Contract.complete_item_status() == "complete"
    assert Contract.owner?(Contract.agent_owner())
    assert Contract.source?(Contract.agent_draft_source())
    assert Contract.criticality?(Contract.informational_criticality())
    assert Contract.item_status?(Contract.complete_item_status())
  end

  test "context enums and agent execution-plan capabilities are owned by the Agent contract" do
    assert Contract.context_kind?(Contract.agent_run_context_kind())
    assert Contract.context_source?(Contract.agent_context_source())
    assert Contract.context_source?(Contract.workflow_context_source())
    assert Contract.context_mode?(Contract.execution_context_mode())

    assert Contract.snapshot_capability() == "agent.execution_plan.snapshot"
    assert Contract.upsert_capability() == "agent.execution_plan.upsert"
    assert Contract.update_item_capability() == "agent.execution_plan.update_item"
    assert Contract.append_evidence_capability() == "agent.execution_plan.append_evidence"
  end

  test "runtime evidence-required criticality rules use the contract predicate" do
    offenders =
      for file <- @criticality_runtime_files,
          criticality <- Contract.evidence_required_criticalities(),
          source = File.read!(file),
          direct_literal?(source, criticality) do
        {file, criticality}
      end

    assert offenders == [],
           "runtime modules must use Contract.evidence_required_criticality?/1; offenders:\n#{format_offenders(offenders)}"
  end

  test "runtime agent-editable item authorization uses the contract values" do
    values = [
      Contract.agent_owner(),
      Contract.agent_draft_source(),
      Contract.informational_criticality(),
      Contract.complete_item_status()
    ]

    offenders =
      for file <- @agent_editable_item_runtime_files,
          value <- values,
          source = File.read!(file),
          direct_literal?(source, value) do
        {file, value}
      end

    assert offenders == [],
           "runtime modules must use Agent execution-plan contract values; offenders:\n#{format_offenders(offenders)}"
  end

  defp direct_literal?(source, value) do
    Regex.match?(~r/"#{Regex.escape(value)}"/, source)
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {file, criticality} -> "- #{file}: #{inspect(criticality)}" end)
  end

  defp transition_targets(transitions) do
    transitions
    |> Map.values()
    |> List.flatten()
  end
end
