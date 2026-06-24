defmodule SymphonyElixir.Agent.ExecutionPlan.Schema do
  @moduledoc """
  Pure schema validation for provider-neutral `agent.execution_plan.v1` records.

  This validator owns only generic plan fields. Workflow profile, route, tracker,
  Workpad, and readiness metadata must live in workflow adoption envelopes or
  namespaced extensions.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Context, as: ContextSchema
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Item, as: ItemSchema
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation, as: SchemaValidation

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation,
    only: [
      collect_unknown_keys: 4,
      collect_required_keys: 4,
      collect_string_field: 4,
      collect_enum_field: 5,
      collect_timestamp_field: 4,
      collect_positive_integer_field: 4,
      collect_extensions: 3
    ]

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan) when is_map(plan) do
    errors =
      []
      |> collect_unknown_keys(plan, Fields.allowed_plan_keys(), [])
      |> collect_required_keys(plan, Fields.required_plan_keys(), [])
      |> collect_schema(plan)
      |> collect_string_field(plan, Fields.plan_id(), [])
      |> ContextSchema.collect(plan)
      |> collect_source_plan_ref(plan)
      |> collect_enum_field(plan, Fields.status(), &Contract.plan_status?/1, [])
      |> ItemSchema.collect(plan)
      |> collect_rendering(plan)
      |> collect_timestamp_field(plan, Fields.created_at(), [])
      |> collect_timestamp_field(plan, Fields.updated_at(), [])
      |> collect_positive_integer_field(plan, Fields.revision(), [])
      |> collect_extensions(plan, [])

    if errors == [] do
      {:ok, plan}
    else
      {:error, validation_error(errors)}
    end
  end

  def validate(_plan) do
    {:error,
     validation_error([
       %{code: ValidationErrorCodes.invalid_type(), path: [], message: "Plan record must be an object."}
     ])}
  end

  @spec normalize(map()) :: {:ok, Record.Plan.t()} | {:error, map()}
  def normalize(plan) do
    with {:ok, valid_plan} <- validate(plan) do
      {:ok, Record.from_map(valid_plan)}
    end
  end

  defp collect_schema(errors, plan) do
    case Map.fetch(plan, Fields.schema()) do
      {:ok, schema} ->
        if schema == Contract.schema_id() do
          errors
        else
          errors ++
            [
              %{
                code: ValidationErrorCodes.invalid_schema(),
                path: [Fields.schema()],
                message: "Unsupported execution plan schema."
              }
            ]
        end

      :error ->
        errors
    end
  end

  defp collect_source_plan_ref(errors, plan) do
    case Map.fetch(plan, Fields.source_plan_ref()) do
      :error ->
        errors

      {:ok, ref} when is_map(ref) ->
        path = [Fields.source_plan_ref()]

        errors
        |> collect_unknown_keys(ref, Fields.allowed_source_plan_ref_keys(), path)
        |> collect_required_keys(ref, Fields.required_source_plan_ref_keys(), path)
        |> collect_string_field(ref, Fields.artifact_id(), path)
        |> collect_string_field(ref, Fields.hash(), path)
        |> collect_extensions(ref, path)

      {:ok, _ref} ->
        errors ++
          [
            %{
              code: ValidationErrorCodes.invalid_type(),
              path: [Fields.source_plan_ref()],
              message: "Source plan ref must be an object with artifact identity."
            }
          ]
    end
  end

  defp collect_rendering(errors, plan) do
    case Map.fetch(plan, Fields.rendering()) do
      :error ->
        errors

      {:ok, rendering} when is_map(rendering) ->
        errors

      {:ok, _rendering} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.rendering()], message: "Rendering metadata must be an object."}]
    end
  end

  defp validation_error(errors),
    do: SchemaValidation.validation_error(errors, "Execution plan failed schema validation.")
end
