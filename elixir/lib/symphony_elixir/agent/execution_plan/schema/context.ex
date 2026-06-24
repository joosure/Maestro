defmodule SymphonyElixir.Agent.ExecutionPlan.Schema.Context do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Contract
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Schema, as: SchemaErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  import SymphonyElixir.Agent.ExecutionPlan.Schema.Validation,
    only: [
      collect_unknown_keys: 4,
      collect_required_keys: 4,
      collect_string_field: 4,
      collect_nullable_string_field: 4,
      collect_enum_field: 5,
      collect_string_list_field: 4,
      collect_positive_integer_field: 4,
      collect_extensions: 3,
      non_empty_string?: 1
    ]

  @spec collect([map()], map()) :: [map()]
  def collect(errors, plan) do
    case Map.fetch(plan, Fields.context()) do
      {:ok, context} when is_map(context) ->
        collect_context_fields(errors, context)

      {:ok, _context} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: [Fields.context()], message: "Context must be an object."}]

      :error ->
        errors
    end
  end

  defp collect_context_fields(errors, context) do
    path = [Fields.context()]

    errors
    |> collect_unknown_keys(context, Fields.allowed_context_keys(), path)
    |> collect_required_keys(context, Fields.required_context_keys(), path)
    |> collect_enum_field(context, Fields.context_kind(), &Contract.context_kind?/1, path)
    |> collect_nullable_string_field(context, Fields.tenant_id(), path)
    |> collect_string_field(context, Fields.workspace_id(), path)
    |> collect_string_field(context, Fields.run_id(), path)
    |> collect_nullable_string_field(context, Fields.agent_session_id(), path)
    |> collect_nullable_string_field(context, Fields.task_id(), path)
    |> collect_nullable_string_field(context, Fields.recipe_run_id(), path)
    |> collect_context_ref(
      context,
      Fields.workflow_ref(),
      Fields.allowed_workflow_ref_keys(),
      &collect_workflow_ref_fields/3,
      [Fields.profile_kind(), Fields.route_key(), Fields.issue_id(), Fields.issue_identifier()],
      path
    )
    |> collect_context_ref(
      context,
      Fields.repo_ref(),
      Fields.allowed_repo_ref_keys(),
      &collect_repo_ref_fields/3,
      [Fields.repository_id()],
      path
    )
    |> collect_context_ref(
      context,
      Fields.tracker_ref(),
      Fields.allowed_tracker_ref_keys(),
      &collect_tracker_ref_fields/3,
      [Fields.issue_id(), Fields.issue_identifier()],
      path
    )
    |> collect_string_list_field(context, Fields.policy_refs(), path)
    |> collect_enum_field(context, Fields.source(), &Contract.context_source?/1, path)
    |> collect_enum_field(context, Fields.mode(), &Contract.context_mode?/1, path)
    |> collect_extensions(context, path)
  end

  defp collect_context_ref(errors, context, key, allowed_keys, field_collector, identity_keys, path) when is_function(field_collector, 3) do
    case Map.fetch(context, key) do
      :error ->
        errors

      {:ok, nil} ->
        errors

      {:ok, ref} when is_map(ref) ->
        ref_path = path ++ [key]

        errors
        |> collect_unknown_keys(ref, allowed_keys, ref_path)
        |> collect_identity_ref(ref, identity_keys, ref_path)
        |> field_collector.(ref, ref_path)

      {:ok, _ref} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be null or a bounded identity object."}]
    end
  end

  defp collect_workflow_ref_fields(errors, ref, path) do
    errors
    |> collect_string_field(ref, Fields.profile_kind(), path)
    |> collect_positive_integer_field(ref, Fields.profile_version(), path)
    |> collect_string_field(ref, Fields.route_key(), path)
    |> collect_string_field(ref, Fields.lifecycle_phase(), path)
    |> collect_string_field(ref, Fields.issue_id(), path)
    |> collect_string_field(ref, Fields.issue_identifier(), path)
    |> collect_string_field(ref, Fields.tracker_kind(), path)
  end

  defp collect_repo_ref_fields(errors, ref, path) do
    errors
    |> collect_string_field(ref, Fields.provider(), path)
    |> collect_string_field(ref, Fields.repository_id(), path)
    |> collect_string_field(ref, Fields.branch(), path)
  end

  defp collect_tracker_ref_fields(errors, ref, path) do
    errors
    |> collect_string_field(ref, Fields.tracker_kind(), path)
    |> collect_string_field(ref, Fields.issue_id(), path)
    |> collect_string_field(ref, Fields.issue_identifier(), path)
  end

  defp collect_identity_ref(errors, ref, identity_keys, path) do
    if Enum.any?(identity_keys, &(ref |> Map.get(&1) |> non_empty_string?())) do
      errors
    else
      errors ++
        [
          %{
            code: SchemaErrorCodes.invalid_identity_ref(),
            path: path,
            message: "Bounded identity references must include at least one stable identity field."
          }
        ]
    end
  end
end
