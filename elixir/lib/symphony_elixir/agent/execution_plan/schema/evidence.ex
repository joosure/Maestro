defmodule SymphonyElixir.Agent.ExecutionPlan.Schema.Evidence do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Evidence, as: EvidenceRefSchema
  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation,
    only: [
      collect_unknown_keys: 4,
      collect_required_keys: 4,
      collect_string_field: 4,
      collect_boolean_field: 4,
      collect_string_list_field: 4,
      collect_optional_map_field: 4,
      collect_extensions: 3,
      non_empty_string?: 1,
      string_list?: 1
    ]

  @spec collect_requirements([map()], map(), [String.t() | non_neg_integer()]) :: [map()]
  def collect_requirements(errors, item, path) do
    case Map.fetch(item, Fields.evidence_requirements()) do
      {:ok, requirements} when is_list(requirements) ->
        evidence_requirement_errors =
          requirements
          |> Enum.with_index()
          |> Enum.flat_map(fn {requirement, index} ->
            validate_evidence_requirement_errors(requirement, path ++ [Fields.evidence_requirements(), index])
          end)

        errors ++ evidence_requirement_errors ++ critical_evidence_requirement_errors(item, path)

      {:ok, _requirements} ->
        errors ++
          [
            %{
              code: ValidationErrorCodes.invalid_type(),
              path: path ++ [Fields.evidence_requirements()],
              message: "Evidence requirements must be an array."
            }
          ]

      :error ->
        errors
    end
  end

  @spec collect_refs([map()], map(), [String.t() | non_neg_integer()]) :: [map()]
  def collect_refs(errors, item, path) do
    case Map.fetch(item, Fields.evidence_refs()) do
      {:ok, refs} when is_list(refs) ->
        ref_errors =
          refs
          |> Enum.with_index()
          |> Enum.flat_map(fn {ref, index} ->
            case EvidenceRefSchema.validate_ref(ref) do
              {:ok, _ref} ->
                []

              {:error, %{errors: errors}} ->
                Enum.map(errors, fn error -> Map.update!(error, :path, &(path ++ [Fields.evidence_refs(), index] ++ &1)) end)
            end
          end)

        errors ++ ref_errors ++ duplicate_evidence_ref_errors(refs, path)

      {:ok, _refs} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [Fields.evidence_refs()], message: "Evidence refs must be an array."}]

      :error ->
        errors
    end
  end

  defp validate_evidence_requirement_errors(requirement, path) when is_map(requirement) do
    []
    |> collect_unknown_keys(requirement, Fields.allowed_evidence_requirement_keys(), path)
    |> collect_required_keys(requirement, Fields.required_evidence_requirement_keys(), path)
    |> collect_string_field(requirement, Fields.evidence_kind(), path)
    |> collect_boolean_field(requirement, Fields.required(), path)
    |> collect_string_list_field(requirement, Fields.required_fields(), path)
    |> collect_trust_class_list_field(requirement, Fields.trust_classes(), path)
    |> collect_optional_map_field(requirement, Fields.matcher(), path)
    |> collect_extensions(requirement, path)
  end

  defp validate_evidence_requirement_errors(_requirement, path) do
    [%{code: ValidationErrorCodes.invalid_type(), path: path, message: "Evidence requirement must be an object."}]
  end

  defp critical_evidence_requirement_errors(item, path) do
    criticality = Map.get(item, Fields.criticality())
    evidence_requirements = Map.get(item, Fields.evidence_requirements())

    if Contract.evidence_required_criticality?(criticality) and evidence_requirements == [] do
      [
        %{
          code: SchemaErrorCodes.missing_evidence_requirements(),
          path: path ++ [Fields.evidence_requirements()],
          message: "Critical or policy-required plan items must declare evidence requirements."
        }
      ]
    else
      []
    end
  end

  defp duplicate_evidence_ref_errors(refs, path) do
    evidence_ids =
      refs
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, Fields.evidence_id()))
      |> Enum.filter(&non_empty_string?/1)

    evidence_ids
    |> Enum.frequencies()
    |> Enum.filter(fn {_evidence_id, count} -> count > 1 end)
    |> Enum.map(fn {evidence_id, _count} ->
      %{
        code: SchemaErrorCodes.duplicate_evidence_id(),
        path: path ++ [Fields.evidence_refs()],
        message: "Evidence ids must be unique per item.",
        evidence_id: evidence_id
      }
    end)
  end

  defp collect_trust_class_list_field(errors, record, key, path) do
    value = Map.get(record, key)

    if Map.has_key?(record, key) and (not string_list?(value) or Enum.any?(value, &(not Contract.trust_class?(&1)))) do
      errors ++ [%{code: ValidationErrorCodes.invalid_enum(), path: path ++ [key], message: "Field must be a list of allowed trust classes."}]
    else
      errors
    end
  end
end
