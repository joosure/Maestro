defmodule SymphonyElixir.Agent.ExecutionPlan.Evidence do
  @moduledoc """
  Generic immutable evidence-ref helpers for execution plan items.

  Domain adoption layers may validate additional scope fields before delegating
  to these helpers, but duplicate handling and append immutability stay generic.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Evidence, as: EvidenceErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation, as: SchemaValidation

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation,
    only: [
      collect_unknown_keys: 4,
      collect_required_keys: 4,
      collect_string_field: 4,
      collect_nullable_string_field: 4,
      collect_enum_field: 5,
      collect_timestamp_field: 4,
      collect_map_field: 4,
      collect_extensions: 3
    ]

  @spec validate_ref(map()) :: {:ok, map()} | {:error, map()}
  def validate_ref(ref) when is_map(ref) do
    errors =
      []
      |> collect_unknown_keys(ref, Fields.allowed_evidence_ref_keys(), [])
      |> collect_required_keys(ref, Fields.required_evidence_ref_keys(), [])
      |> collect_string_field(ref, Fields.evidence_id(), [])
      |> collect_string_field(ref, Fields.evidence_kind(), [])
      |> collect_enum_field(ref, Fields.source(), &Contract.trust_class?/1, [])
      |> collect_string_field(ref, Fields.producer(), [])
      |> collect_nullable_string_field(ref, Fields.evidence_context_key(), [])
      |> collect_nullable_string_field(ref, Fields.run_id(), [])
      |> collect_nullable_string_field(ref, Fields.task_id(), [])
      |> collect_timestamp_field(ref, Fields.observed_at(), [])
      |> collect_map_field(ref, Fields.payload(), [])
      |> collect_extensions(ref, [])

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
  def append_ref(item, evidence_ref), do: append_ref(item, evidence_ref, &validate_ref/1)

  @spec append_ref(map(), map(), (map() -> {:ok, map()} | {:error, map()})) :: {:ok, map()} | {:error, map()}
  def append_ref(item, evidence_ref, validator) when is_map(item) and is_map(evidence_ref) and is_function(validator, 1) do
    with {:ok, ref} <- validator.(evidence_ref),
         {:ok, refs} <- evidence_refs(item) do
      append_valid_ref(item, refs, ref)
    end
  end

  def append_ref(_item, _evidence_ref, _validator) do
    {:error,
     %{
       code: EvidenceErrorCodes.invalid_evidence_ref(),
       message: "Evidence reference append requires an item object and evidence reference object."
     }}
  end

  defp append_valid_ref(item, refs, ref) do
    case Enum.find(refs, &(Map.get(&1, Fields.evidence_id()) == Map.fetch!(ref, Fields.evidence_id()))) do
      nil ->
        {:ok, Map.put(item, Fields.evidence_refs(), refs ++ [ref])}

      ^ref ->
        {:ok, item}

      _different_ref ->
        {:error,
         %{
           code: EvidenceErrorCodes.evidence_ref_conflict(),
           message: "Evidence references are immutable once attached.",
           evidence_id: Map.fetch!(ref, Fields.evidence_id())
         }}
    end
  end

  defp evidence_refs(item) when is_map(item) do
    case Map.get(item, Fields.evidence_refs()) do
      refs when is_list(refs) -> {:ok, refs}
      _refs -> invalid_evidence_refs()
    end
  end

  defp invalid_evidence_refs do
    {:error,
     %{
       code: EvidenceErrorCodes.invalid_evidence_refs(),
       message: "Plan item evidence_refs must be an array before evidence can be appended."
     }}
  end

  defp validation_error(errors) do
    SchemaValidation.validation_error(errors, "Evidence reference failed schema validation.")
  end
end
