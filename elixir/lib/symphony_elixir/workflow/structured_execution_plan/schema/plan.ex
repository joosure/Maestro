defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Plan do
  @moduledoc """
  Validates canonical `workflow.execution_plan.v1` plan envelopes.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Item
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Profile

  @validation_error_message "Structured execution plan failed schema validation."

  @spec validate(map()) :: {:ok, map()} | {:error, map()}
  def validate(plan) when is_map(plan) do
    errors =
      []
      |> Validation.collect_unknown_keys(plan, Fields.allowed_plan_keys(), [])
      |> Validation.collect_required_keys(plan, Fields.required_plan_keys(), [])
      |> collect_schema(plan)
      |> Validation.collect_string_field(plan, Fields.plan_id(), [])
      |> Validation.collect_string_field(plan, Fields.run_id(), [])
      |> Validation.collect_string_field(plan, Fields.issue_id(), [])
      |> Validation.collect_string_field(plan, Fields.issue_identifier(), [])
      |> Validation.collect_string_field(plan, Fields.tracker_kind(), [])
      |> Profile.collect(plan)
      |> Validation.collect_string_field(plan, Fields.route_key(), [])
      |> collect_route_ref(plan)
      |> Validation.collect_string_field(plan, Fields.lifecycle_phase(), [])
      |> Validation.collect_enum_field(plan, Fields.status(), &Contract.plan_status?/1, [])
      |> Item.collect(plan)
      |> Validation.collect_map_field(plan, Fields.rendering(), [])
      |> Validation.collect_timestamp_field(plan, Fields.created_at(), [])
      |> Validation.collect_timestamp_field(plan, Fields.updated_at(), [])
      |> Validation.collect_positive_integer_field(plan, Fields.revision(), [])
      |> Validation.collect_extensions(plan, [])

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
                message: "Unsupported structured plan schema."
              }
            ]
        end

      :error ->
        errors
    end
  end

  defp collect_route_ref(errors, plan) do
    workflow_profile = Map.get(plan, Fields.workflow_profile())
    route_key = Map.get(plan, Fields.route_key())

    if is_map(workflow_profile) and is_binary(route_key) do
      validate_route_ref(errors, workflow_profile, route_key)
    else
      errors
    end
  end

  defp validate_route_ref(errors, workflow_profile, route_key) do
    case RouteRef.new(workflow_profile, route_key) do
      {:ok, _route_ref} ->
        errors

      {:error, reason} ->
        errors ++
          [
            %{
              code: ErrorCodes.invalid_route_ref(),
              path: [Fields.route_key()],
              message: "Route key is not supported by the workflow profile.",
              reason: inspect(reason)
            }
          ]
    end
  end

  defp validation_error(errors), do: Validation.validation_error(errors, @validation_error_message)
end
