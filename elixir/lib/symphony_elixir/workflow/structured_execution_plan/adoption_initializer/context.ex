defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Context do
  @moduledoc """
  Build attrs for profile-owned structured execution plan adoption modules.

  This module consumes the stable `AdoptionInitializer.Request` struct and
  builds the string-keyed attrs consumed by profile adoption modules.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Identifiers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Request
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Result
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @plan_id_key Fields.plan_id()
  @run_id_key Fields.run_id()
  @issue_id_key Fields.issue_id()
  @issue_identifier_key Fields.issue_identifier()
  @tracker_kind_key Fields.tracker_kind()
  @route_key_key Fields.route_key()
  @status_key Fields.status()
  @created_at_key Fields.created_at()
  @updated_at_key Fields.updated_at()

  @required_context_keys [@run_id_key, @issue_id_key, @tracker_kind_key]

  @spec build_attrs(Request.t(), map()) :: {:ok, map()} | {:error, map()}
  def build_attrs(%Request{} = request, resolved_profile) when is_map(resolved_profile) do
    route_key = request.run_context.route_key
    run_id = request.run_context.run_id
    issue_id = request.issue_context.issue_id
    tracker_kind = request.tracker_context.tracker_kind

    plan_id =
      request.run_context.plan_id ||
        Identifiers.default_plan_id(run_id, resolved_profile.kind, resolved_profile.version, route_key)

    created_at = request.run_context.created_at || current_timestamp()

    attrs =
      %{
        @plan_id_key => plan_id,
        @run_id_key => run_id,
        @issue_id_key => issue_id,
        @tracker_kind_key => tracker_kind,
        @created_at_key => created_at
      }
      |> put_optional(@issue_identifier_key, request.issue_context.issue_identifier)
      |> put_optional(@route_key_key, route_key)
      |> put_optional(@status_key, request.run_context.status)
      |> put_optional(@updated_at_key, request.run_context.updated_at)

    missing = Enum.reject(@required_context_keys, &present?(Map.get(attrs, &1)))

    if missing == [] do
      {:ok, attrs}
    else
      Result.missing_context(missing)
    end
  end

  defp current_timestamp do
    DateTime.utc_now(:second) |> DateTime.to_iso8601()
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
