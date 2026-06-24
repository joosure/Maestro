defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Guards do
  @moduledoc """
  Guard helpers for workflow structured execution-plan tool commands.

  These helpers operate on canonical workflow plan records and parsed command
  arguments. They do not parse raw Dynamic Tool input.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentExecutionPlanContract
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.ErrorCodes, as: ToolErrorCodes

  @revision_key Fields.revision()
  @items_key Fields.items()
  @preview_mode ToolContract.preview_mode()

  @spec ensure_revision(map(), pos_integer()) :: :ok | {:error, map()}
  def ensure_revision(%{@revision_key => revision}, revision), do: :ok

  def ensure_revision(%{@revision_key => revision}, expected_revision) do
    {:error,
     %{
       code: ToolErrorCodes.revision_conflict(),
       message: "Structured execution plan revision does not match the caller-observed revision.",
       current_revision: revision,
       expected_revision: expected_revision
     }}
  end

  @spec fetch_item(map(), String.t()) :: {:ok, map()} | {:error, map()}
  def fetch_item(%{@items_key => items}, item_id) when is_list(items) do
    case Enum.find(items, &(Map.get(&1, AgentFields.item_id()) == item_id)) do
      nil -> {:error, item_not_found(item_id)}
      item -> {:ok, item}
    end
  end

  def fetch_item(_plan, item_id), do: {:error, item_not_found(item_id)}

  @spec ensure_completion_allowed(map(), String.t()) :: :ok | {:error, map()}
  def ensure_completion_allowed(item, status) do
    if status == AgentExecutionPlanContract.complete_item_status() and evidence_bound_critical_item?(item) and not Reconciler.satisfied?(item) do
      {:error,
       %{
         code: ToolErrorCodes.missing_required_evidence(),
         message: "Evidence-bound critical items cannot be completed without satisfying evidence.",
         item_id: Map.get(item, AgentFields.item_id())
       }}
    else
      :ok
    end
  end

  @spec ensure_preview_render_mode(String.t()) :: :ok | {:error, term()}
  def ensure_preview_render_mode(@preview_mode), do: :ok

  def ensure_preview_render_mode(_mode) do
    {:error, {:invalid_arguments, "Structured plan Workpad tool currently supports preview mode only."}}
  end

  defp evidence_bound_critical_item?(item) do
    Contract.evidence_required_criticality?(Map.get(item, AgentFields.criticality())) and
      Map.get(item, AgentFields.evidence_requirements(), []) != []
  end

  defp item_not_found(item_id) do
    %{
      code: ToolErrorCodes.item_not_found(),
      message: "Structured execution plan item was not found.",
      item_id: item_id
    }
  end
end
