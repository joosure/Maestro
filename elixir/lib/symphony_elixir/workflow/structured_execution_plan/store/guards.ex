defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Guards do
  @moduledoc """
  Workflow structured-plan store guard policies.

  These helpers consume canonical workflow records and lookup results. They do
  not parse raw config, call storage backends, or mutate records.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes

  @spec plan_id_available({:ok, map()} | {:error, map()}, map()) :: :ok | {:error, map()}
  def plan_id_available(fetch_result, plan) when is_map(plan) do
    plan_id = Map.fetch!(plan, Fields.plan_id())

    case fetch_result do
      {:ok, _envelope} ->
        {:error,
         %{
           code: ErrorCodes.plan_conflict(),
           message: "A structured execution plan with this plan_id already exists.",
           plan_id: plan_id
         }}

      {:error, %{code: code} = reason} ->
        if code == ErrorCodes.plan_not_found(), do: :ok, else: {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec active_slot_available({:ok, String.t()} | {:error, map()}, map(), String.t() | nil) :: :ok | {:error, map()}
  def active_slot_available(active_result, plan, current_plan_id) when is_map(plan) do
    if Map.get(plan, Fields.status()) == Contract.active_plan_status() do
      active_slot_available_result(active_result, plan, current_plan_id)
    else
      :ok
    end
  end

  defp active_slot_available_result({:ok, current_plan_id}, _plan, current_plan_id), do: :ok

  defp active_slot_available_result({:ok, active_plan_id}, plan, _current_plan_id) do
    {:error,
     %{
       code: ErrorCodes.plan_conflict(),
       message: "An active structured execution plan already exists for this run/profile/route.",
       active_plan_id: active_plan_id,
       run_id: Map.get(plan, Fields.run_id()),
       route_key: Map.get(plan, Fields.route_key())
     }}
  end

  defp active_slot_available_result({:error, %{code: code} = reason}, _plan, _current_plan_id) do
    if code == ErrorCodes.plan_not_found(), do: :ok, else: {:error, reason}
  end

  defp active_slot_available_result({:error, reason}, _plan, _current_plan_id), do: {:error, reason}

  @spec revision_matches(map(), pos_integer()) :: :ok | {:error, map()}
  def revision_matches(plan, expected_revision) when is_map(plan) do
    revision = Map.fetch!(plan, Fields.revision())

    if revision == expected_revision do
      :ok
    else
      {:error,
       %{
         code: ErrorCodes.revision_conflict(),
         message: "Structured execution plan revision does not match the caller-observed revision.",
         current_revision: revision,
         expected_revision: expected_revision
       }}
    end
  end

  @spec plan_mutable(map()) :: :ok | {:error, map()}
  def plan_mutable(plan) when is_map(plan) do
    status = Map.get(plan, Fields.status())

    if Contract.terminal_plan_status?(status) do
      {:error,
       %{
         code: ErrorCodes.item_update_not_allowed(),
         message: "Closed or superseded structured execution plans do not accept item updates.",
         plan_id: Map.get(plan, Fields.plan_id()),
         status: status
       }}
    else
      :ok
    end
  end
end
