defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence do
  @moduledoc """
  Immutable evidence reference shape for structured execution plan items.

  Phase 1 stores and validates references only. Binding typed-tool results to
  evidence and recomputing item completion belongs to a later phase.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Evidence, as: AgentExecutionPlanEvidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @spec validate_ref(map()) :: {:ok, map()} | {:error, map()}
  def validate_ref(ref) when is_map(ref) do
    generic_ref = Map.delete(ref, Fields.issue_id())

    errors =
      []
      |> collect_generic_ref_errors(generic_ref)
      |> collect_required_keys(ref, Fields.evidence_scope_keys(), [])
      |> collect_string_field(ref, Fields.issue_id(), [])

    if errors == [] do
      {:ok, ref}
    else
      {:error, validation_error(errors)}
    end
  end

  def validate_ref(_ref) do
    {:error,
     validation_error([
       %{code: ValidationErrorCodes.invalid_type(), path: [], message: "Evidence reference must be an object."}
     ])}
  end

  @spec append_ref(map(), map()) :: {:ok, map()} | {:error, map()}
  def append_ref(item, evidence_ref) when is_map(item) and is_map(evidence_ref) do
    AgentExecutionPlanEvidence.append_ref(item, evidence_ref, &validate_ref/1)
  end

  def append_ref(_item, _evidence_ref) do
    {:error,
     %{
       code: EvidenceErrorCodes.invalid_evidence_ref(),
       message: "Evidence reference append requires an item object and evidence reference object."
     }}
  end

  defp collect_generic_ref_errors(errors, generic_ref) do
    case AgentExecutionPlanEvidence.validate_ref(generic_ref) do
      {:ok, _ref} ->
        errors

      {:error, %{errors: generic_errors}} ->
        errors ++ generic_errors
    end
  end

  defp collect_required_keys(errors, record, required_keys, path) do
    required_errors =
      required_keys
      |> Enum.reject(&Map.has_key?(record, &1))
      |> Enum.map(fn key ->
        %{code: ValidationErrorCodes.missing_required_field(), path: path ++ [key], message: "Required field is missing."}
      end)

    errors ++ required_errors
  end

  defp collect_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be a non-empty string."}]
    else
      errors
    end
  end

  defp validation_error(errors) do
    %{code: ValidationErrorCodes.schema_invalid(), message: "Evidence reference failed schema validation.", errors: errors}
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
