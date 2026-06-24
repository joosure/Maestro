defmodule SymphonyElixir.Agent.ExecutionPlan.ErrorCodeBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.StatusMachine, as: StatusMachineErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Store, as: StoreErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Tool, as: ToolErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes

  @runtime_files [
    "lib/symphony_elixir/agent/execution_plan/evidence.ex",
    "lib/symphony_elixir/agent/execution_plan/schema.ex",
    "lib/symphony_elixir/agent/execution_plan/status_machine.ex",
    "lib/symphony_elixir/agent/execution_plan/store.ex",
    "lib/symphony_elixir/agent/execution_plan/store/client.ex",
    "lib/symphony_elixir/agent/execution_plan/store/commands.ex",
    "lib/symphony_elixir/agent/execution_plan/store/error_results.ex",
    "lib/symphony_elixir/agent/execution_plan/store/guards.ex",
    "lib/symphony_elixir/agent/execution_plan/store/mutations.ex",
    "lib/symphony_elixir/agent/execution_plan/store/persistence.ex",
    "lib/symphony_elixir/agent/execution_plan/store/server.ex",
    "lib/symphony_elixir/agent/execution_plan/tool_executor.ex",
    "lib/symphony_elixir/workflow/structured_execution_plan/evidence.ex",
    "lib/symphony_elixir/workflow/structured_execution_plan/status_machine.ex"
  ]

  @legacy_error_code_modules [
    "SymphonyElixir.Agent.ExecutionPlan.Validation.ErrorCodes",
    "SymphonyElixir.Agent.ExecutionPlan.Evidence.ErrorCodes",
    "SymphonyElixir.Agent.ExecutionPlan.Schema.ErrorCodes",
    "SymphonyElixir.Agent.ExecutionPlan.StatusMachine.ErrorCodes"
  ]

  test "runtime modules read machine codes through contracts" do
    forbidden_literals = validation_codes() ++ schema_codes() ++ status_machine_codes() ++ store_codes() ++ tool_codes() ++ evidence_codes()

    offenders =
      for file <- @runtime_files,
          code <- forbidden_literals,
          source = File.read!(file),
          direct_code_literal?(source, code) do
        {file, code}
      end

    assert offenders == [],
           "runtime modules must use Agent execution-plan error-code contracts; offenders:\n#{format_offenders(offenders)}"
  end

  test "error-code contracts live under the unified Agent execution-plan namespace" do
    production_files =
      "lib/symphony_elixir"
      |> Path.join("**/*.ex")
      |> Path.wildcard()

    offenders =
      for file <- production_files,
          module_name <- @legacy_error_code_modules,
          source = File.read!(file),
          String.contains?(source, module_name) do
        {file, module_name}
      end

    assert offenders == [],
           "legacy nested error-code modules must not be referenced; offenders:\n#{format_offenders(offenders)}"
  end

  defp validation_codes do
    [
      ValidationErrorCodes.schema_invalid(),
      ValidationErrorCodes.invalid_schema(),
      ValidationErrorCodes.invalid_type(),
      ValidationErrorCodes.invalid_enum(),
      ValidationErrorCodes.unknown_key(),
      ValidationErrorCodes.missing_required_field(),
      ValidationErrorCodes.invalid_extension_key()
    ]
  end

  defp evidence_codes do
    [
      EvidenceErrorCodes.invalid_evidence_ref(),
      EvidenceErrorCodes.invalid_evidence_refs(),
      EvidenceErrorCodes.evidence_ref_conflict(),
      EvidenceErrorCodes.evidence_scope_mismatch(),
      EvidenceErrorCodes.evidence_requirements_unsatisfied()
    ]
  end

  defp schema_codes do
    [
      SchemaErrorCodes.duplicate_item_id(),
      SchemaErrorCodes.missing_evidence_requirements(),
      SchemaErrorCodes.duplicate_evidence_id(),
      SchemaErrorCodes.invalid_dependency(),
      SchemaErrorCodes.dependency_cycle(),
      SchemaErrorCodes.invalid_identity_ref()
    ]
  end

  defp status_machine_codes do
    [
      StatusMachineErrorCodes.plan_status_transition_forbidden(),
      StatusMachineErrorCodes.item_status_transition_forbidden()
    ]
  end

  defp store_codes do
    [
      StoreErrorCodes.plan_conflict(),
      StoreErrorCodes.plan_not_found(),
      StoreErrorCodes.plan_id_mismatch(),
      StoreErrorCodes.revision_conflict(),
      StoreErrorCodes.item_update_not_allowed(),
      StoreErrorCodes.item_not_found(),
      StoreErrorCodes.store_unavailable()
    ]
  end

  defp tool_codes do
    [
      ToolErrorCodes.invalid_arguments(),
      ToolErrorCodes.unsupported_tool(),
      ToolErrorCodes.tool_failed()
    ]
  end

  defp direct_code_literal?(source, code) do
    Regex.match?(~r/"#{Regex.escape(code)}"/, source)
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {file, code} -> "- #{file}: #{inspect(code)}" end)
  end
end
