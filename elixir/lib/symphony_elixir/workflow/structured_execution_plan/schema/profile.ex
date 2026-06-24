defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Schema.Profile do
  @moduledoc """
  Validates canonical workflow profile references inside workflow plans.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Schema.Validation
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @spec collect([map()], map()) :: [map()]
  def collect(errors, plan) when is_map(plan) do
    case Map.fetch(plan, Fields.workflow_profile()) do
      {:ok, profile} when is_map(profile) ->
        collect_profile_fields(errors, profile)

      {:ok, _profile} ->
        errors ++
          [
            %{
              code: ValidationErrorCodes.invalid_type(),
              path: [Fields.workflow_profile()],
              message: "Workflow profile must be an object."
            }
          ]

      :error ->
        errors
    end
  end

  defp collect_profile_fields(errors, profile) do
    path = [Fields.workflow_profile()]

    errors
    |> Validation.collect_unknown_keys(profile, Fields.allowed_profile_keys(), path)
    |> Validation.collect_required_keys(profile, Fields.required_profile_keys(), path)
    |> Validation.collect_string_field(profile, Fields.profile_kind(), path)
    |> Validation.collect_positive_integer_field(profile, Fields.profile_version(), path)
    |> Validation.collect_extensions(profile, path)
  end
end
