defmodule SymphonyElixir.Agent.ExecutionPlan.ToolExecutor do
  @moduledoc """
  Executes generic Agent execution-plan typed tools.

  The executor is intentionally not wired into the default Dynamic Tool source.
  It dispatches canonical Agent execution-plan tool names and orchestrates Store
  calls over parsed command structs; workflow handoff readiness remains
  authoritative in workflow policy modules.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Store
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Arguments, as: ToolArguments

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Command.{
    AppendEvidenceRef,
    Create,
    MergeItems,
    Snapshot,
    UpdateItem
  }

  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Guards, as: ToolGuards
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Options, as: ToolOptions
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Payload, as: ToolPayload
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Result, as: ToolResult

  @snapshot_tool ToolContract.snapshot_tool()
  @upsert_tool ToolContract.upsert_tool()
  @update_item_tool ToolContract.update_item_tool()
  @append_evidence_tool ToolContract.append_evidence_tool()

  @spec tool_specs(keyword()) :: [map()]
  def tool_specs(opts \\ []) when is_list(opts) do
    if Keyword.get(opts, :expose?, true), do: ToolContract.tool_specs(), else: []
  end

  @spec supported_tool_names(keyword()) :: [String.t()]
  def supported_tool_names(opts \\ []) when is_list(opts) do
    if Keyword.get(opts, :expose?, true), do: ToolContract.tools(), else: []
  end

  @spec execute(String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(tool, arguments, opts \\ [])

  def execute(@snapshot_tool, arguments, opts), do: plan_snapshot(arguments, opts)
  def execute(@upsert_tool, arguments, opts), do: plan_upsert(arguments, opts)
  def execute(@update_item_tool, arguments, opts), do: plan_update_item(arguments, opts)
  def execute(@append_evidence_tool, arguments, opts), do: plan_append_evidence(arguments, opts)
  def execute(tool, _arguments, _opts), do: ToolResult.failure({:unsupported_tool, tool})

  defp plan_snapshot(arguments, opts) do
    with {:ok, %Snapshot{plan_id: plan_id}} <- ToolArguments.snapshot(arguments),
         {:ok, plan} <- Store.fetch(plan_id, ToolOptions.store_opts(opts)) do
      ToolResult.success(plan, [])
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end

  defp plan_upsert(arguments, opts) do
    case ToolArguments.upsert(arguments) do
      {:ok, %Create{plan: plan}} ->
        case Store.create(ToolPayload.plan_map(plan), ToolOptions.store_opts(opts)) do
          {:ok, created_plan} -> ToolResult.success(created_plan, ToolResult.created_items(created_plan))
          {:error, reason} -> ToolResult.failure(reason)
        end

      {:ok, %MergeItems{plan_id: plan_id, plan_revision: plan_revision, items: items}} ->
        store_opts = ToolOptions.store_opts(opts)

        with {:ok, before_plan} <- Store.fetch(plan_id, store_opts),
             {:ok, updated_plan} <- Store.upsert_agent_items(plan_id, ToolPayload.item_maps(items), plan_revision, store_opts) do
          ToolResult.success(updated_plan, ToolResult.changed_items(before_plan, updated_plan))
        else
          {:error, reason} -> ToolResult.failure(reason)
        end

      {:error, reason} ->
        ToolResult.failure(reason)
    end
  end

  defp plan_update_item(arguments, opts) do
    store_opts = ToolOptions.store_opts(opts)

    with {:ok, %UpdateItem{} = command} <- ToolArguments.update_item(arguments),
         {:ok, plan} <- Store.fetch(command.plan_id, store_opts),
         :ok <- ToolGuards.ensure_agent_owned_update(plan, command),
         {:ok, updated_plan} <- Store.update_item_status(command.plan_id, command.item_id, command.status, command.plan_revision, store_opts),
         {:ok, updated_item} <- ToolGuards.fetch_item(updated_plan, command.item_id) do
      ToolResult.success(updated_plan, [updated_item])
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end

  defp plan_append_evidence(arguments, opts) do
    store_opts = ToolOptions.store_opts(opts)

    with {:ok, %AppendEvidenceRef{} = command} <- ToolArguments.append_evidence(arguments),
         {:ok, updated_plan} <-
           Store.append_evidence_ref(
             command.plan_id,
             command.item_id,
             ToolPayload.evidence_ref_map(command.evidence_ref),
             command.plan_revision,
             store_opts
           ),
         {:ok, updated_item} <- ToolGuards.fetch_item(updated_plan, command.item_id) do
      ToolResult.success(updated_plan, [updated_item])
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end
end
