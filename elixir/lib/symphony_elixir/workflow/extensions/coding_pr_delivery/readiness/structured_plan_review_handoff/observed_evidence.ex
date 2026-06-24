defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.ObservedEvidence do
  @moduledoc """
  Bounded observed-evidence diagnostics for structured-plan review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.Plan.Evidence
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: StructuredPlanContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Projection, as: StructuredPlanProjection

  @schema StructuredPlanContract.schema_id()
  @observed_plan_id_field "plan_id"
  @observed_status_field "status"
  @observed_head_sha_field "head_sha"
  @observed_item_field "item"
  @observed_item_status_field "item_status"
  @observed_evidence_refs_field "evidence_refs"
  @observed_error_field "error"
  @observed_options_value_type_field "options.value_type"

  @spec plan(map()) :: [String.t()]
  def plan(plan) when is_map(plan) do
    [
      @schema,
      if(present?(StructuredPlanProjection.plan_id(plan)), do: observed_field(@observed_plan_id_field)),
      if(present?(StructuredPlanProjection.status(plan)), do: observed_field(@observed_status_field, StructuredPlanProjection.status(plan))),
      if(present?(Evidence.latest_repo_head(plan)), do: observed_field(@observed_head_sha_field))
    ]
    |> Enum.reject(&is_nil/1)
  end

  def plan(_plan), do: []

  @spec category([map()], map()) :: [String.t()]
  def category(items, category) do
    evidence_kinds = Map.fetch!(category, :evidence_kinds)

    items
    |> Enum.flat_map(fn item ->
      refs = Evidence.category_refs(item, evidence_kinds)

      [
        observed_field(@observed_item_field, StructuredPlanProjection.item_id(item)),
        observed_field(@observed_item_status_field, StructuredPlanProjection.item_status(item)),
        observed_category_field(Map.fetch!(category, :key), @observed_evidence_refs_field, length(refs))
      ]
    end)
    |> Enum.uniq()
  end

  @spec error(map()) :: [String.t()]
  def error(%{code: code}) when is_binary(code), do: [observed_field(@observed_error_field, code)]
  def error(%{code: code}) when is_atom(code), do: [observed_field(@observed_error_field, Atom.to_string(code))]
  def error(_reason), do: []

  @spec options_error(map()) :: [String.t()]
  def options_error(%{value_type: value_type}) when is_binary(value_type) do
    [observed_field(@observed_options_value_type_field, value_type)]
  end

  def options_error(_reason), do: []

  defp observed_field(field), do: "#{@schema}.#{field}"
  defp observed_field(field, value), do: "#{@schema}.#{field}=#{value}"
  defp observed_category_field(category_key, field, value), do: "#{@schema}.#{category_key}.#{field}=#{value}"

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
