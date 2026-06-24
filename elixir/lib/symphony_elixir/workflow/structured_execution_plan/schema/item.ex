defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Item do
  @moduledoc """
  Validates canonical Agent item records inside workflow adoption plans.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Requirement

  @spec collect([map()], map()) :: [map()]
  def collect(errors, plan) when is_map(plan) do
    case Map.fetch(plan, Fields.items()) do
      {:ok, items} when is_list(items) ->
        item_errors =
          items
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} -> validate_errors(item, index) end)

        errors ++ item_errors ++ duplicate_item_id_errors(items)

      {:ok, _items} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.items()], message: "Items must be an array."}]

      :error ->
        errors
    end
  end

  @spec validate_errors(term(), non_neg_integer()) :: [map()]
  def validate_errors(item, index) when is_map(item) do
    path = [Fields.items(), index]

    []
    |> Validation.collect_unknown_keys(item, AgentFields.allowed_item_keys(), path)
    |> Validation.collect_required_keys(item, AgentFields.required_item_keys(), path)
    |> Validation.collect_string_field(item, AgentFields.item_id(), path)
    |> Validation.collect_nullable_string_field(item, AgentFields.parent_item_id(), path)
    |> Validation.collect_string_field(item, AgentFields.title(), path)
    |> Validation.collect_enum_field(item, AgentFields.kind(), &Contract.item_kind?/1, path)
    |> Validation.collect_enum_field(item, AgentFields.status(), &Contract.item_status?/1, path)
    |> Validation.collect_boolean_field(item, AgentFields.required(), path)
    |> Validation.collect_enum_field(item, AgentFields.criticality(), &Contract.criticality?/1, path)
    |> Validation.collect_enum_field(item, AgentFields.owned_by(), &Contract.owner?/1, path)
    |> Validation.collect_enum_field(item, AgentFields.source(), &Contract.source?/1, path)
    |> Validation.collect_string_list_field(item, AgentFields.depends_on(), path)
    |> collect_evidence_requirements(item, path)
    |> collect_evidence_refs(item, path)
    |> Validation.collect_timestamp_field(item, AgentFields.created_at(), path)
    |> Validation.collect_timestamp_field(item, AgentFields.updated_at(), path)
    |> Validation.collect_positive_integer_field(item, AgentFields.revision(), path)
    |> Validation.collect_extensions(item, path)
  end

  def validate_errors(_item, index) do
    [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.items(), index], message: "Plan item must be an object."}]
  end

  defp duplicate_item_id_errors(items) do
    item_ids =
      items
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, AgentFields.item_id()))
      |> Enum.filter(&Validation.non_empty_string?/1)

    item_ids
    |> Enum.frequencies()
    |> Enum.filter(fn {_item_id, count} -> count > 1 end)
    |> Enum.map(fn {item_id, _count} ->
      %{code: SchemaErrorCodes.duplicate_item_id(), path: [Fields.items()], message: "Plan item ids must be unique.", item_id: item_id}
    end)
  end

  defp collect_evidence_requirements(errors, item, path) do
    case Map.fetch(item, AgentFields.evidence_requirements()) do
      {:ok, requirements} when is_list(requirements) ->
        evidence_requirement_errors =
          requirements
          |> Enum.with_index()
          |> Enum.flat_map(fn {requirement, index} ->
            Requirement.validate_errors(requirement, path ++ [AgentFields.evidence_requirements(), index])
          end)

        errors ++ evidence_requirement_errors ++ critical_evidence_requirement_errors(item, path)

      {:ok, _requirements} ->
        errors ++
          [
            %{
              code: ValidationErrorCodes.invalid_type(),
              path: path ++ [AgentFields.evidence_requirements()],
              message: "Evidence requirements must be an array."
            }
          ]

      :error ->
        errors
    end
  end

  defp critical_evidence_requirement_errors(item, path) do
    criticality = Map.get(item, AgentFields.criticality())
    evidence_requirements = Map.get(item, AgentFields.evidence_requirements())

    if Contract.evidence_required_criticality?(criticality) and evidence_requirements == [] do
      [
        %{
          code: SchemaErrorCodes.missing_evidence_requirements(),
          path: path ++ [AgentFields.evidence_requirements()],
          message: "Critical or policy-required plan items must declare evidence requirements."
        }
      ]
    else
      []
    end
  end

  defp collect_evidence_refs(errors, item, path) do
    case Map.fetch(item, AgentFields.evidence_refs()) do
      {:ok, refs} when is_list(refs) ->
        ref_errors =
          refs
          |> Enum.with_index()
          |> Enum.flat_map(fn {ref, index} ->
            case Evidence.validate_ref(ref) do
              {:ok, _ref} ->
                []

              {:error, %{errors: errors}} ->
                Enum.map(errors, fn error -> Map.update!(error, :path, &(path ++ [AgentFields.evidence_refs(), index] ++ &1)) end)
            end
          end)

        errors ++ ref_errors ++ duplicate_evidence_ref_errors(refs, path)

      {:ok, _refs} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [AgentFields.evidence_refs()], message: "Evidence refs must be an array."}]

      :error ->
        errors
    end
  end

  defp duplicate_evidence_ref_errors(refs, path) do
    refs
    |> Enum.filter(&is_map/1)
    |> Enum.map(&Map.get(&1, AgentFields.evidence_id()))
    |> Enum.filter(&Validation.non_empty_string?/1)
    |> Enum.frequencies()
    |> Enum.filter(fn {_evidence_id, count} -> count > 1 end)
    |> Enum.map(fn {evidence_id, _count} ->
      %{
        code: SchemaErrorCodes.duplicate_evidence_id(),
        path: path ++ [AgentFields.evidence_refs()],
        message: "Evidence ids must be unique per item.",
        evidence_id: evidence_id
      }
    end)
  end
end
