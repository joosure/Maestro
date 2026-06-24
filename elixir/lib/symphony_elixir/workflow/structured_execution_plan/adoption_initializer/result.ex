defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Result do
  @moduledoc """
  Result and error payload builders for structured-plan adoption initialization.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @kind_key "kind"
  @version_key "version"
  @snapshot_item_count_key "item_count"

  @plan_id_key Fields.plan_id()
  @run_id_key Fields.run_id()
  @workflow_profile_key Fields.workflow_profile()
  @route_key_key Fields.route_key()
  @status_key Fields.status()
  @items_key Fields.items()
  @revision_key Fields.revision()

  @spec created(map()) :: {:ok, map()}
  def created(plan) when is_map(plan) do
    {:ok, %{status: :created, plan: plan, snapshot: snapshot(plan)}}
  end

  @spec skipped(:gate_disabled | :profile_not_adopted, map() | nil) :: {:ok, map()}
  def skipped(reason, profile), do: {:ok, %{status: :skipped, reason: reason, profile: profile}}

  @spec profile_snapshot(map()) :: map()
  def profile_snapshot(resolved_profile) when is_map(resolved_profile) do
    %{@kind_key => resolved_profile.kind, @version_key => resolved_profile.version}
  end

  @spec profile_resolution_failed(term()) :: {:error, map()}
  def profile_resolution_failed(reason) do
    {:error,
     %{
       code: ErrorCodes.profile_resolution_failed(),
       message: "Structured execution plan adoption could not resolve the workflow profile.",
       reason: inspect(reason)
     }}
  end

  @spec invalid_adoption_module(module()) :: {:error, map()}
  def invalid_adoption_module(module) when is_atom(module) do
    {:error,
     %{
       code: ErrorCodes.invalid_adoption_module(),
       message: "Workflow profile structured execution plan adoption module does not export build/1.",
       module: inspect(module)
     }}
  end

  @spec missing_context([String.t()]) :: {:error, map()}
  def missing_context(fields) when is_list(fields) do
    {:error,
     %{
       code: ErrorCodes.missing_context(),
       message: "Structured execution plan adoption is missing required run or issue context.",
       fields: fields
     }}
  end

  defp snapshot(plan) do
    %{
      @plan_id_key => Map.fetch!(plan, @plan_id_key),
      @run_id_key => Map.fetch!(plan, @run_id_key),
      @workflow_profile_key => Map.fetch!(plan, @workflow_profile_key),
      @route_key_key => Map.fetch!(plan, @route_key_key),
      @status_key => Map.fetch!(plan, @status_key),
      @revision_key => Map.fetch!(plan, @revision_key),
      @snapshot_item_count_key => plan |> Map.fetch!(@items_key) |> length()
    }
  end
end
