defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Projector do
  @moduledoc """
  Projects canonical workflow plan records into Markdown-ready summaries.

  Projection consumes already validated plan records and item lists. It does not
  parse rendered Markdown, prompt text, or tracker comment bodies.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Labels
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Syntax
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Text

  @type metadata_entry :: %{required(:label) => String.t(), required(:value) => String.t()}
  @type item_entry :: %{
          required(:complete?) => boolean(),
          required(:item_id) => String.t(),
          required(:title) => String.t(),
          required(:status) => String.t(),
          required(:kind) => String.t(),
          required(:owned_by) => String.t(),
          required(:evidence_summary) => String.t()
        }
  @type section :: %{required(:label) => String.t(), required(:items) => [item_entry()]}
  @type projection :: %{required(:metadata) => [metadata_entry()], required(:sections) => [section()], required(:truncated?) => boolean()}

  @status_key Fields.status()
  @criticality_key AgentFields.criticality()
  @item_id_key AgentFields.item_id()
  @title_key AgentFields.title()
  @kind_key AgentFields.kind()
  @owned_by_key AgentFields.owned_by()
  @evidence_refs_key AgentFields.evidence_refs()
  @evidence_kind_key AgentFields.evidence_kind()

  @spec project(map(), [map()], boolean()) :: projection()
  def project(plan, visible_items, items_truncated?) when is_map(plan) and is_list(visible_items) and is_boolean(items_truncated?) do
    %{
      metadata: metadata(plan),
      sections: sections(visible_items),
      truncated?: items_truncated?
    }
  end

  defp metadata(plan) do
    Labels.metadata_labels()
    |> Enum.map(fn {key, label} ->
      %{label: label, value: Text.inline_code(Map.fetch!(plan, key))}
    end)
  end

  defp sections(items) do
    Labels.section_labels()
    |> Enum.flat_map(fn {criticality, label} ->
      section_items =
        items
        |> Enum.filter(&(Map.get(&1, @criticality_key) == criticality))
        |> Enum.map(&item/1)

      case section_items do
        [] -> []
        values -> [%{label: label, items: values}]
      end
    end)
  end

  defp item(item) do
    status = Map.get(item, @status_key)

    %{
      complete?: Contract.completed_item_status?(status),
      item_id: Text.inline_code(Map.get(item, @item_id_key)),
      title: Text.bounded(Map.get(item, @title_key)),
      status: Text.inline_code(status),
      kind: Text.inline_code(Map.get(item, @kind_key)),
      owned_by: Text.inline_code(Map.get(item, @owned_by_key)),
      evidence_summary: evidence_summary(Map.get(item, @evidence_refs_key, []))
    }
  end

  defp evidence_summary([]), do: Labels.none_label()

  defp evidence_summary(refs) when is_list(refs) do
    refs
    |> Enum.map(&Map.get(&1, @evidence_kind_key))
    |> Enum.filter(&is_binary/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {kind, _count} -> kind end)
    |> Enum.map(fn {kind, count} -> Syntax.counted_value(Text.bounded(kind), count) end)
    |> Syntax.join_details()
    |> case do
      "" -> Labels.none_label()
      summary -> summary
    end
  end

  defp evidence_summary(_refs), do: Labels.none_label()
end
