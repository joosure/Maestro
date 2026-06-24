defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ToolExecutor do
  @moduledoc """
  Executes canonical workflow structured execution-plan typed tools.

  Provider-facing aliases are normalized by `DynamicToolSource` before they
  reach this module. This executor only dispatches canonical tool names and
  orchestrates Store/Renderer calls over parsed command arguments.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Arguments, as: ToolArguments
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Guards, as: ToolGuards
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Result, as: ToolResult
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Renderer

  @snapshot_tool ToolContract.snapshot_tool()
  @upsert_tool ToolContract.upsert_tool()
  @update_item_tool ToolContract.update_item_tool()
  @render_workpad_tool ToolContract.render_workpad_tool()

  @spec tool_specs() :: [map()]
  def tool_specs, do: ToolContract.tool_specs()

  @spec supported_tool_names() :: [String.t()]
  def supported_tool_names, do: ToolContract.tools()

  @spec execute(String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(tool, arguments, opts \\ [])

  def execute(@snapshot_tool, arguments, opts), do: plan_snapshot(arguments, opts)
  def execute(@upsert_tool, arguments, opts), do: plan_upsert(arguments, opts)
  def execute(@update_item_tool, arguments, opts), do: plan_update_item(arguments, opts)
  def execute(@render_workpad_tool, arguments, opts), do: plan_render_workpad(arguments, opts)
  def execute(tool, _arguments, _opts), do: ToolResult.failure({:unsupported_tool, tool})

  defp plan_snapshot(arguments, opts) do
    with {:ok, args} <- ToolArguments.snapshot(arguments),
         {:ok, plan} <- fetch_plan(args, opts) do
      ToolResult.success(plan, [])
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end

  defp plan_upsert(arguments, opts) do
    case ToolArguments.upsert(arguments) do
      {:ok, {:create, plan}} ->
        case Store.create(plan, store_opts(opts)) do
          {:ok, created_plan} -> ToolResult.success(created_plan, Map.get(created_plan, Fields.items(), []))
          {:error, reason} -> ToolResult.failure(reason)
        end

      {:ok, {:merge_items, plan_id, plan_revision, items}} ->
        with {:ok, before_plan} <- Store.fetch(plan_id, store_opts(opts)),
             {:ok, updated_plan} <- Store.upsert_agent_items(plan_id, items, plan_revision, store_opts(opts)) do
          ToolResult.success(updated_plan, ToolResult.changed_items(before_plan, updated_plan))
        else
          {:error, reason} -> ToolResult.failure(reason)
        end

      {:error, reason} ->
        ToolResult.failure(reason)
    end
  end

  defp plan_update_item(arguments, opts) do
    with {:ok, args} <- ToolArguments.update_item(arguments),
         {:ok, plan} <- Store.fetch(args.plan_id, store_opts(opts)),
         :ok <- ToolGuards.ensure_revision(plan, args.plan_revision),
         {:ok, item} <- ToolGuards.fetch_item(plan, args.item_id),
         :ok <- ToolGuards.ensure_completion_allowed(item, args.status),
         {:ok, updated_plan} <- Store.update_item_status(args.plan_id, args.item_id, args.status, args.plan_revision, store_opts(opts)),
         {:ok, updated_item} <- ToolGuards.fetch_item(updated_plan, args.item_id) do
      ToolResult.success(updated_plan, [updated_item])
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end

  defp plan_render_workpad(arguments, opts) do
    with {:ok, args} <- ToolArguments.render_workpad(arguments),
         :ok <- ToolGuards.ensure_preview_render_mode(args.mode),
         {:ok, plan} <- Store.fetch(args.plan_id, store_opts(opts)),
         :ok <- ToolGuards.ensure_revision(plan, args.plan_revision),
         {:ok, rendered_workpad} <- Renderer.render(plan, ToolArguments.render_opts(args)) do
      ToolResult.success(plan, [], %{ToolContract.rendered_workpad_key() => rendered_workpad})
    else
      {:error, reason} -> ToolResult.failure(reason)
    end
  end

  defp fetch_plan(%{plan_id: plan_id}, opts), do: Store.fetch(plan_id, store_opts(opts))

  defp fetch_plan(%{run_id: run_id, workflow_profile: workflow_profile, route_key: route_key}, opts) do
    Store.active_plan(run_id, workflow_profile, route_key, store_opts(opts))
  end

  defp store_opts(opts) do
    []
    |> maybe_put(:server, Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store))
    |> maybe_put(:updated_at, Keyword.get(opts, :updated_at))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
