defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Requirements do
  @moduledoc """
  Matches canonical evidence refs against item evidence requirements.

  This module consumes already-normalized `agent.execution_plan.v1` item maps.
  It does not read raw provider payload aliases or atom-keyed input.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.EvidencePolicy

  @spec satisfied?(map()) :: boolean()
  def satisfied?(item) when is_map(item) do
    requirements = list_value(Map.get(item, AgentFields.evidence_requirements()))
    refs = list_value(Map.get(item, AgentFields.evidence_refs()))

    requirements_satisfied?(requirements, refs)
  end

  def satisfied?(_item), do: false

  @spec requirement_kinds(map()) :: [String.t()]
  def requirement_kinds(item) when is_map(item) do
    item
    |> Map.get(AgentFields.evidence_requirements())
    |> list_value()
    |> Enum.flat_map(fn
      %{} = requirement ->
        case Map.get(requirement, AgentFields.evidence_kind()) do
          evidence_kind when is_binary(evidence_kind) -> [evidence_kind]
          _other -> []
        end

      _requirement ->
        []
    end)
  end

  def requirement_kinds(_item), do: []

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []

  defp requirements_satisfied?(requirements, refs) when is_list(requirements) and is_list(refs) do
    requirements != [] and Enum.all?(requirements, &requirement_satisfied?(&1, refs))
  end

  defp requirements_satisfied?(_requirements, _refs), do: false

  defp requirement_satisfied?(%{} = requirement, refs) do
    evidence_kind = Map.get(requirement, AgentFields.evidence_kind())

    is_binary(evidence_kind) and Enum.any?(refs, &ref_satisfies_requirement?(&1, requirement, evidence_kind))
  end

  defp requirement_satisfied?(_requirement, _refs), do: false

  defp ref_satisfies_requirement?(%{} = ref, requirement, evidence_kind) do
    payload = Map.get(ref, AgentFields.payload())

    Map.get(ref, AgentFields.evidence_kind()) == evidence_kind and
      is_map(payload) and
      Map.get(ref, AgentFields.source()) in Map.get(requirement, AgentFields.trust_classes(), []) and
      required_fields_present?(payload, Map.get(requirement, AgentFields.required_fields(), [])) and
      EvidencePolicy.valid?(evidence_kind, payload)
  end

  defp ref_satisfies_requirement?(_ref, _requirement, _evidence_kind), do: false

  defp required_fields_present?(payload, required_fields) when is_map(payload) and is_list(required_fields) do
    Enum.all?(required_fields, &present?(Map.get(payload, &1)))
  end

  defp required_fields_present?(_payload, _required_fields), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_boolean(value), do: true
  defp present?(value) when is_integer(value), do: true
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
