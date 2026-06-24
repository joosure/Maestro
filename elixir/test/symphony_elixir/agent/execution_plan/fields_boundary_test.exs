defmodule SymphonyElixir.Agent.ExecutionPlan.FieldsBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @core_runtime_files [
    "lib/symphony_elixir/agent/execution_plan/evidence.ex",
    "lib/symphony_elixir/agent/execution_plan/record.ex",
    "lib/symphony_elixir/agent/execution_plan/record/context_ref.ex",
    "lib/symphony_elixir/agent/execution_plan/record/context.ex",
    "lib/symphony_elixir/agent/execution_plan/record/evidence.ex",
    "lib/symphony_elixir/agent/execution_plan/record/item.ex",
    "lib/symphony_elixir/agent/execution_plan/record/metadata.ex",
    "lib/symphony_elixir/agent/execution_plan/record/plan.ex",
    "lib/symphony_elixir/agent/execution_plan/schema.ex",
    "lib/symphony_elixir/agent/execution_plan/schema/context.ex",
    "lib/symphony_elixir/agent/execution_plan/schema/dependency.ex",
    "lib/symphony_elixir/agent/execution_plan/schema/evidence.ex",
    "lib/symphony_elixir/agent/execution_plan/schema/item.ex",
    "lib/symphony_elixir/agent/execution_plan/store.ex",
    "lib/symphony_elixir/agent/execution_plan/store/commands.ex",
    "lib/symphony_elixir/agent/execution_plan/store/guards.ex",
    "lib/symphony_elixir/agent/execution_plan/store/mutations.ex",
    "lib/symphony_elixir/agent/execution_plan/store/persistence.ex",
    "lib/symphony_elixir/agent/execution_plan/storage/memory_backend.ex",
    "lib/symphony_elixir/agent/execution_plan/storage/sqlite_backend.ex"
  ]

  test "core runtime modules read canonical field keys through Fields" do
    field_literals = canonical_field_literals()

    offenders =
      for file <- @core_runtime_files,
          field <- field_literals,
          source = File.read!(file),
          direct_field_literal?(source, field) do
        {file, field}
      end

    assert offenders == [],
           "core Agent execution-plan runtime modules must use Fields for canonical field keys; offenders:\n#{format_offenders(offenders)}"
  end

  defp canonical_field_literals do
    [
      Fields.allowed_plan_keys(),
      Fields.allowed_source_plan_ref_keys(),
      Fields.allowed_context_keys(),
      Fields.allowed_workflow_ref_keys(),
      Fields.allowed_repo_ref_keys(),
      Fields.allowed_tracker_ref_keys(),
      Fields.allowed_item_keys(),
      Fields.allowed_status_reason_keys(),
      Fields.allowed_evidence_requirement_keys(),
      Fields.allowed_evidence_ref_keys()
    ]
    |> List.flatten()
    |> Enum.uniq()
  end

  defp direct_field_literal?(source, field) do
    Regex.match?(~r/"#{Regex.escape(field)}"/, source)
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {file, field} -> "- #{file}: #{inspect(field)}" end)
  end
end
