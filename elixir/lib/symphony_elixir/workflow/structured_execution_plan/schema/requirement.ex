defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Requirement do
  @moduledoc """
  Validates canonical Agent evidence requirement records used by workflow items.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract

  @spec validate_errors(term(), [String.t() | non_neg_integer()]) :: [map()]
  def validate_errors(requirement, path) when is_map(requirement) do
    []
    |> Validation.collect_unknown_keys(requirement, AgentFields.allowed_evidence_requirement_keys(), path)
    |> Validation.collect_required_keys(requirement, AgentFields.required_evidence_requirement_keys(), path)
    |> Validation.collect_string_field(requirement, AgentFields.evidence_kind(), path)
    |> Validation.collect_boolean_field(requirement, AgentFields.required(), path)
    |> Validation.collect_string_list_field(requirement, AgentFields.required_fields(), path)
    |> Validation.collect_enum_list_field(
      requirement,
      AgentFields.trust_classes(),
      &Contract.trust_class?/1,
      path,
      "Field must be a list of allowed structured execution plan trust classes."
    )
    |> Validation.collect_map_field(requirement, AgentFields.matcher(), path)
    |> Validation.collect_extensions(requirement, path)
  end

  def validate_errors(_requirement, path) do
    [%{code: ValidationErrorCodes.invalid_type(), path: path, message: "Evidence requirement must be an object."}]
  end
end
