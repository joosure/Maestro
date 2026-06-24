defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Result do
  @moduledoc """
  Result envelopes and bounded summaries for workflow structured-plan tools.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Serializer}
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract, as: ToolContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.ErrorCodes, as: ToolErrorCodes

  @max_summary_items 100

  @summary_plan_keys [
    Fields.schema(),
    Fields.plan_id(),
    Fields.run_id(),
    Fields.issue_id(),
    Fields.issue_identifier(),
    Fields.tracker_kind(),
    Fields.workflow_profile(),
    Fields.route_key(),
    Fields.lifecycle_phase(),
    Fields.status(),
    Fields.created_at(),
    Fields.updated_at(),
    Fields.revision()
  ]

  @summary_item_keys [
    AgentFields.item_id(),
    AgentFields.parent_item_id(),
    AgentFields.title(),
    AgentFields.kind(),
    AgentFields.status(),
    AgentFields.required(),
    AgentFields.criticality(),
    AgentFields.owned_by(),
    AgentFields.source(),
    AgentFields.depends_on(),
    AgentFields.evidence_requirements(),
    AgentFields.created_at(),
    AgentFields.updated_at(),
    AgentFields.revision()
  ]

  @spec success(map(), [map()]) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def success(plan, changed_items), do: success(plan, changed_items, %{})

  @spec success(map(), [map()], map()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def success(plan, changed_items, extra) when is_map(plan) and is_list(changed_items) and is_map(extra) do
    plan
    |> success_result(changed_items)
    |> Map.merge(extra)
    |> success_payload()
    |> then(&{:success, &1})
  end

  @spec failure(term()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def failure(reason) do
    {code, message, details} = typed_error(reason)

    {:failure,
     %{
       ToolContract.error_key() => %{
         ToolContract.code_key() => code,
         ToolContract.message_key() => message,
         ToolContract.details_key() => Serializer.json_safe_value(details)
       }
     }}
  end

  @spec changed_items(map(), map()) :: [map()]
  def changed_items(before_plan, updated_plan) do
    before_by_id =
      before_plan
      |> Map.get(Fields.items(), [])
      |> Map.new(&{Map.get(&1, AgentFields.item_id()), &1})

    updated_plan
    |> Map.get(Fields.items(), [])
    |> Enum.reject(fn item -> Map.get(before_by_id, Map.get(item, AgentFields.item_id())) == item end)
  end

  defp success_result(plan, changed_items) do
    %{
      ToolContract.success_key() => true,
      ToolContract.plan_key() => plan_summary(plan),
      ToolContract.changed_items_key() => Enum.map(changed_items, &item_summary/1),
      ToolContract.errors_key() => [],
      ToolContract.warnings_key() => []
    }
  end

  defp plan_summary(plan) do
    items = Map.get(plan, Fields.items(), [])
    summary_items = Enum.take(items, @max_summary_items)

    plan
    |> Map.take(@summary_plan_keys)
    |> Map.put(Fields.items(), Enum.map(summary_items, &item_summary/1))
    |> Map.put(ToolContract.item_count_key(), length(items))
    |> Map.put(ToolContract.items_truncated_key(), length(items) > @max_summary_items)
  end

  defp item_summary(item) do
    evidence_refs = Map.get(item, AgentFields.evidence_refs(), [])

    item
    |> Map.take(@summary_item_keys)
    |> Map.put(ToolContract.evidence_ref_count_key(), length(evidence_refs))
    |> Map.put(ToolContract.evidence_kinds_key(), evidence_refs |> Enum.map(&Map.get(&1, AgentFields.evidence_kind())) |> Enum.reject(&is_nil/1) |> Enum.uniq())
  end

  defp success_payload(data, warnings \\ []) do
    %{
      ToolContract.data_key() => Serializer.json_safe_value(data),
      ToolContract.warnings_key() => Serializer.json_safe_value(warnings)
    }
  end

  defp typed_error({:invalid_arguments, message}), do: {ToolErrorCodes.invalid_arguments(), message, %{}}

  defp typed_error({:unsupported_tool, tool}) do
    {ToolErrorCodes.unsupported_tool(), "Structured execution plan tool is not supported.", %{Metadata.Contract.tool() => tool}}
  end

  defp typed_error(%{code: code, message: message} = error) do
    {to_string(code), message, Map.delete(error, :message)}
  end

  defp typed_error(reason) do
    {ToolErrorCodes.tool_failed(), "Structured execution plan tool execution failed.", %{ToolContract.reason_key() => inspect(reason)}}
  end
end
