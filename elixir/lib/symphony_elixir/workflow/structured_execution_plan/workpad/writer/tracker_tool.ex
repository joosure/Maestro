defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.TrackerTool do
  @moduledoc """
  Tracker typed-tool boundary for structured-plan Workpad writes.

  Provider/tracker-specific tool names belong here, not in the public writer
  facade. The writer core passes canonical rendered Workpad facts into this
  boundary and receives normalized write metadata back.
  """

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: RenderingContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Writer.Result

  @mode_key "mode"
  @replace_mode "replace"

  @issue_id_arg Fields.issue_id()
  @heading_arg RenderingContract.heading_key()
  @body_arg RenderingContract.body_key()
  @workpad_id_arg RenderingContract.workpad_id_key()

  @tracker_upsert_workpad_capability TrackerCapabilities.upsert_workpad()

  @comment_key "comment"
  @data_key "data"
  @payload_key "payload"
  @id_key "id"
  @name_key "name"

  @spec write(map(), map(), map(), Options.t()) :: {:ok, map()} | {:error, map()}
  def write(plan, rendered, decision, %Options{} = options) when is_map(decision) do
    if Map.get(decision, Result.action_key()) == Result.write_action() do
      with {:ok, executor} <- tracker_executor(options),
           {:ok, tool} <- tracker_tool(plan, options),
           {:ok, workpad} <- execute_tracker_write(executor, tool, tracker_arguments(plan, rendered, decision), options),
           {:ok, workpad_id} <- workpad_id(workpad) do
        {:ok, Result.tracker_success(tool, workpad, workpad_id)}
      end
    else
      {:error, Result.failure("Unsupported structured plan Workpad write action.")}
    end
  end

  defp execute_tracker_write(executor, tool, arguments, %Options{} = options) do
    case executor.(tool, arguments, options.tracker_opts) do
      {:success, payload} ->
        extract_comment(payload)

      {:failure, payload} ->
        {:error, Result.tracker_failure({:failure, payload})}

      {:error, reason} ->
        {:error, Result.tracker_failure({:error, reason})}

      other ->
        {:error, Result.tracker_failure({:unsupported, other})}
    end
  end

  defp extract_comment(%{@data_key => %{@comment_key => comment}}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{@comment_key => comment}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{@payload_key => %{@data_key => %{@comment_key => comment}}}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(%{@payload_key => %{@comment_key => comment}}) when is_map(comment), do: {:ok, comment}
  defp extract_comment(payload), do: {:error, Result.missing_comment_metadata(payload)}

  defp tracker_arguments(plan, rendered, decision) do
    workpad_id = Map.get(decision, @workpad_id_arg) || get_in(plan, [Fields.rendering(), @workpad_id_arg])

    %{
      @issue_id_arg => Map.fetch!(plan, Fields.issue_id()),
      @heading_arg => Map.fetch!(rendered, RenderingContract.heading_key()),
      @body_arg => Map.fetch!(rendered, RenderingContract.body_key()),
      @mode_key => @replace_mode
    }
    |> maybe_put(@workpad_id_arg, workpad_id)
  end

  defp tracker_executor(%Options{tracker_executor: executor}) when is_function(executor, 3), do: {:ok, executor}

  defp tracker_executor(_options), do: {:error, Result.failure("tracker_executor function is required when Workpad rendering is enabled.")}

  defp tracker_tool(plan, %Options{tracker_tool: override}) do
    case override || default_tracker_tool(plan) do
      tool when is_binary(tool) -> {:ok, tool}
      _tool -> {:error, Result.failure("A supported tracker Workpad tool is required.")}
    end
  end

  defp default_tracker_tool(plan) do
    tracker_kind = Map.get(plan, Fields.tracker_kind())

    with kind when is_binary(kind) <- tracker_kind,
         [%{} = spec | _rest] <- tracker_tool_specs(kind, @tracker_upsert_workpad_capability),
         tool when is_binary(tool) <- Map.get(spec, @name_key) do
      tool
    else
      _missing_tool -> nil
    end
  end

  defp tracker_tool_specs(tracker_kind, capability) do
    %{kind: tracker_kind}
    |> Tracker.dynamic_tools()
    |> Enum.filter(&(Map.get(&1, Metadata.Contract.capability()) == capability))
  end

  defp workpad_id(%{@id_key => id}) when is_binary(id), do: {:ok, id}
  defp workpad_id(_workpad), do: {:error, Result.failure("Tracker Workpad write did not return a workpad id.")}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
