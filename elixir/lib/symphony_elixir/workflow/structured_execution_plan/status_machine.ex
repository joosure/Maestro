defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.StatusMachine do
  @moduledoc """
  Pure status transition table for canonical plan and item records.
  """

  @plan_transitions %{
    "draft" => ~w(active superseded),
    "active" => ~w(blocked handoff_ready closed superseded),
    "blocked" => ~w(active closed),
    "handoff_ready" => ~w(active closed),
    "closed" => [],
    "superseded" => []
  }

  @item_transitions %{
    "pending" => ~w(in_progress complete blocked skipped),
    "in_progress" => ~w(complete blocked failed),
    "blocked" => ~w(pending in_progress),
    "failed" => ~w(pending superseded),
    "complete" => ~w(in_progress superseded),
    "skipped" => ~w(pending),
    "superseded" => []
  }

  @spec allowed_plan_transition?(term(), term()) :: boolean()
  def allowed_plan_transition?(from_status, to_status) do
    transition_allowed?(@plan_transitions, from_status, to_status)
  end

  @spec allowed_item_transition?(term(), term()) :: boolean()
  def allowed_item_transition?(from_status, to_status) do
    transition_allowed?(@item_transitions, from_status, to_status)
  end

  @spec validate_plan_transition(term(), term()) :: :ok | {:error, map()}
  def validate_plan_transition(from_status, to_status) do
    if allowed_plan_transition?(from_status, to_status) do
      :ok
    else
      {:error,
       %{
         code: "plan_status_transition_forbidden",
         message: "Plan status transition is not allowed.",
         from_status: from_status,
         to_status: to_status
       }}
    end
  end

  @spec validate_item_transition(term(), term()) :: :ok | {:error, map()}
  def validate_item_transition(from_status, to_status) do
    if allowed_item_transition?(from_status, to_status) do
      :ok
    else
      {:error,
       %{
         code: "item_status_transition_forbidden",
         message: "Item status transition is not allowed.",
         from_status: from_status,
         to_status: to_status
       }}
    end
  end

  defp transition_allowed?(transitions, from_status, to_status) when is_binary(from_status) and is_binary(to_status) do
    to_status in Map.get(transitions, from_status, [])
  end

  defp transition_allowed?(_transitions, _from_status, _to_status), do: false
end
