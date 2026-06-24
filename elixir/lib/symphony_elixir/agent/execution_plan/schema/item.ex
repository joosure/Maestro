defmodule SymphonyElixir.Agent.ExecutionPlan.Schema.Item do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Dependency
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Evidence

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation,
    only: [
      collect_unknown_keys: 4,
      collect_required_keys: 4,
      collect_string_field: 4,
      collect_nullable_string_field: 4,
      collect_enum_field: 5,
      collect_boolean_field: 4,
      collect_string_list_field: 4,
      collect_timestamp_field: 4,
      collect_positive_integer_field: 4,
      collect_extensions: 3
    ]

  @reason_statuses [
    Contract.blocked_item_status(),
    Contract.skipped_item_status(),
    Contract.failed_item_status()
  ]

  @spec collect([map()], map()) :: [map()]
  def collect(errors, plan) do
    case Map.fetch(plan, Fields.items()) do
      {:ok, items} when is_list(items) ->
        item_errors =
          items
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} -> validate_item_errors(item, index) end)

        errors ++ item_errors ++ Dependency.errors(items)

      {:ok, _items} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.items()], message: "Items must be an array."}]

      :error ->
        errors
    end
  end

  defp validate_item_errors(item, index) when is_map(item) do
    path = [Fields.items(), index]

    []
    |> collect_unknown_keys(item, Fields.allowed_item_keys(), path)
    |> collect_required_keys(item, Fields.required_item_keys(), path)
    |> collect_string_field(item, Fields.item_id(), path)
    |> collect_nullable_string_field(item, Fields.parent_item_id(), path)
    |> collect_string_field(item, Fields.title(), path)
    |> collect_enum_field(item, Fields.kind(), &Contract.item_kind?/1, path)
    |> collect_enum_field(item, Fields.status(), &Contract.item_status?/1, path)
    |> collect_boolean_field(item, Fields.required(), path)
    |> collect_enum_field(item, Fields.criticality(), &Contract.criticality?/1, path)
    |> collect_enum_field(item, Fields.owned_by(), &Contract.owner?/1, path)
    |> collect_enum_field(item, Fields.source(), &Contract.source?/1, path)
    |> collect_string_list_field(item, Fields.depends_on(), path)
    |> Evidence.collect_requirements(item, path)
    |> Evidence.collect_refs(item, path)
    |> collect_status_reason(item, path)
    |> collect_timestamp_field(item, Fields.created_at(), path)
    |> collect_timestamp_field(item, Fields.updated_at(), path)
    |> collect_positive_integer_field(item, Fields.revision(), path)
    |> collect_extensions(item, path)
  end

  defp validate_item_errors(_item, index) do
    [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.items(), index], message: "Plan item must be an object."}]
  end

  defp collect_status_reason(errors, item, path) do
    reason_path = path ++ [Fields.status_reason()]

    errors
    |> collect_required_status_reason(item, reason_path)
    |> collect_status_reason_shape(item, reason_path)
  end

  defp collect_required_status_reason(errors, item, reason_path) do
    if Map.get(item, Fields.status()) in @reason_statuses and not Map.has_key?(item, Fields.status_reason()) do
      errors ++
        [
          %{
            code: ValidationErrorCodes.missing_required_field(),
            path: reason_path,
            message: "Blocked, skipped, and failed item statuses require a bounded status_reason."
          }
        ]
    else
      errors
    end
  end

  defp collect_status_reason_shape(errors, item, reason_path) do
    case Map.fetch(item, Fields.status_reason()) do
      {:ok, reason} when is_map(reason) ->
        errors
        |> collect_unknown_keys(reason, Fields.allowed_status_reason_keys(), reason_path)
        |> collect_required_keys(reason, Fields.required_status_reason_keys(), reason_path)
        |> collect_string_field(reason, Fields.reason_code(), reason_path)
        |> collect_nullable_string_field(reason, Fields.actor(), reason_path)
        |> collect_nullable_string_field(reason, Fields.evidence_id(), reason_path)
        |> collect_nullable_string_field(reason, Fields.message(), reason_path)
        |> collect_extensions(reason, reason_path)

      {:ok, _reason} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: reason_path, message: "Status reason must be an object."}]

      :error ->
        errors
    end
  end
end
