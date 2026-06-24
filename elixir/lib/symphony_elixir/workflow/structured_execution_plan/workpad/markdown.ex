defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown do
  @moduledoc """
  Markdown body assembly for canonical workflow structured-plan facts.

  This module combines projected facts into Markdown. It does not own labels,
  syntax tokens, text normalization, or plan/evidence summary policy.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Labels
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Projector
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Markdown.Syntax
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Marker

  @spec body(map(), [map()], String.t(), map(), boolean()) :: String.t()
  def body(plan, visible_items, heading, marker, items_truncated?)
      when is_map(plan) and is_list(visible_items) and is_binary(heading) and is_map(marker) and is_boolean(items_truncated?) do
    projection = Projector.project(plan, visible_items, items_truncated?)

    [
      Syntax.heading(2, heading),
      Marker.line(marker),
      Syntax.blank_line(),
      metadata_lines(projection.metadata),
      Syntax.blank_line(),
      section_lines(projection.sections),
      truncated_line(projection.truncated?)
    ]
    |> Syntax.join_lines()
  end

  defp metadata_lines(metadata) do
    Enum.map(metadata, fn %{label: label, value: value} ->
      Syntax.metadata_line(label, Syntax.inline_code(value))
    end)
  end

  defp section_lines([]), do: [Syntax.blank_line(), Labels.empty_items_message(), Syntax.blank_line()]

  defp section_lines(sections) do
    Enum.flat_map(sections, fn %{label: label, items: items} ->
      [Syntax.blank_line(), Syntax.heading(3, label), Syntax.blank_line() | Enum.map(items, &item_line/1)]
    end)
  end

  defp item_line(item) do
    Syntax.task_item(
      Map.fetch!(item, :complete?),
      Syntax.inline_code(Map.fetch!(item, :item_id)),
      Map.fetch!(item, :title),
      [
        Syntax.detail(Labels.item_status_label(), Syntax.inline_code(Map.fetch!(item, :status))),
        Syntax.detail(Labels.item_kind_label(), Syntax.inline_code(Map.fetch!(item, :kind))),
        Syntax.detail(Labels.item_owner_label(), Syntax.inline_code(Map.fetch!(item, :owned_by))),
        Syntax.detail(Labels.evidence_label(), Map.fetch!(item, :evidence_summary))
      ]
    )
  end

  defp truncated_line(false), do: nil
  defp truncated_line(true), do: [Syntax.blank_line(), Labels.truncated_items_message()]
end
