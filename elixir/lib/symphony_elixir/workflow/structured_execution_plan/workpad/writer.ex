defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer do
  @moduledoc """
  Gated backend writer for rendered structured execution plan Workpads.

  This module is not a Dynamic Tool source. Callers must explicitly provide a
  tracker Workpad typed-tool executor, and the structured-plan render gate must
  be enabled. Rendered Workpad text remains one-way output from canonical plan
  state; tracker Workpad identity is carried by `workpad_id`, not by comment
  body inspection.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: RenderingContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Marker
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Decision
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Guards
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Result
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.TrackerTool

  @type tracker_executor :: (String.t(), map(), keyword() -> {:success, term()} | {:failure, term()} | {:error, term()})

  @spec write(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def write(plan_id, opts \\ [])

  def write(plan_id, opts) when is_binary(plan_id) and is_list(opts) do
    options = Options.parse(opts)

    with :ok <- Guards.ensure_gates(options.gates),
         {:ok, plan} <- Store.fetch(plan_id, options.store_opts),
         :ok <- Guards.ensure_writable_plan(plan),
         {:ok, rendered} <- Renderer.render(plan, options.render_opts),
         {:ok, decision} <- Decision.for_plan(plan),
         {:ok, result} <- TrackerTool.write(plan, rendered, decision, options),
         {:ok, updated_plan} <- maybe_record_marker(plan, rendered, result, options) do
      {:ok, Result.success(plan, rendered, decision, result, updated_plan)}
    else
      {:skip, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(_plan_id, _opts), do: {:error, Result.failure("plan_id must be a string.")}

  defp maybe_record_marker(plan, rendered, result, %Options{} = options) do
    workpad_id = Map.get(result, RenderingContract.workpad_id_key())
    marker = rendered |> Map.fetch!(RenderingContract.marker_key()) |> Marker.put_workpad_id(workpad_id)

    case Store.record_render_marker(Map.fetch!(plan, Fields.plan_id()), marker, Map.fetch!(plan, Fields.revision()), options.store_opts) do
      {:ok, updated_plan} ->
        {:ok, updated_plan}

      {:error, reason} ->
        {:error, Result.failure("Rendered Workpad marker could not be recorded.", %{"reason" => reason})}
    end
  end
end
