defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Guards do
  @moduledoc """
  Gate and mutability checks for structured-plan Workpad writing.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Result

  @enabled_gate Contract.enabled_gate_key()
  @render_workpad_gate Contract.render_workpad_gate_key()

  @spec ensure_gates(map()) :: :ok | {:skip, map()} | {:error, map()}
  def ensure_gates(gates) do
    structured_enabled? = gate_enabled?(gates, @enabled_gate)
    render_enabled? = gate_enabled?(gates, @render_workpad_gate)

    cond do
      structured_enabled? and render_enabled? ->
        :ok

      render_enabled? and not structured_enabled? ->
        {:error, Result.failure("Structured plan Workpad rendering requires structured execution plans to be enabled.")}

      true ->
        {:skip, Result.gate_disabled(@render_workpad_gate)}
    end
  end

  @spec ensure_writable_plan(map()) :: :ok | {:error, map()}
  def ensure_writable_plan(%{} = plan) do
    status = Map.get(plan, Fields.status())

    if Contract.terminal_plan_status?(status) do
      {:error,
       Result.failure(
         "Closed or superseded structured execution plans do not accept Workpad rendering.",
         %{Fields.plan_id() => Map.get(plan, Fields.plan_id()), Fields.status() => status}
       )}
    else
      :ok
    end
  end

  defp gate_enabled?(gates, key) when is_map(gates), do: Map.get(gates, key) == true
  defp gate_enabled?(_gates, _key), do: false
end
