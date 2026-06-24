defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Projection do
  @moduledoc """
  Public read projection for canonical workflow structured execution plans.

  External workflow plugins should use this selector boundary instead of reading
  raw JSON map fields directly. The underlying persisted shape remains owned by
  `Workflow.StructuredExecutionPlan`; plugins consume only stable projections.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler

  @spec plan_id(map()) :: String.t() | nil
  def plan_id(plan), do: string_field(plan, Fields.plan_id())

  @spec status(map()) :: String.t() | nil
  def status(plan), do: string_field(plan, Fields.status())

  @spec run_id(map()) :: String.t() | nil
  def run_id(plan), do: string_field(plan, Fields.run_id())

  @spec issue_id(map()) :: String.t() | nil
  def issue_id(plan), do: string_field(plan, Fields.issue_id())

  @spec issue_identifier(map()) :: String.t() | nil
  def issue_identifier(plan), do: string_field(plan, Fields.issue_identifier())

  @spec route_key(map()) :: String.t() | nil
  def route_key(plan), do: string_field(plan, Fields.route_key())

  @spec workflow_profile(map()) :: map() | nil
  def workflow_profile(plan) when is_map(plan) do
    case Map.get(plan, Fields.workflow_profile()) do
      profile when is_map(profile) -> profile
      _profile -> nil
    end
  end

  def workflow_profile(_plan), do: nil

  @spec items(map()) :: [map()]
  def items(plan) when is_map(plan) do
    case Map.get(plan, Fields.items()) do
      items when is_list(items) -> Enum.filter(items, &is_map/1)
      _items -> []
    end
  end

  def items(_plan), do: []

  @spec item_id(map()) :: String.t() | nil
  def item_id(item), do: string_field(item, AgentFields.item_id())

  @spec item_status(map()) :: String.t() | nil
  def item_status(item), do: string_field(item, AgentFields.status())

  @spec item_required?(map()) :: boolean()
  def item_required?(item) when is_map(item), do: Map.get(item, AgentFields.required()) == true
  def item_required?(_item), do: false

  @spec item_criticality(map()) :: String.t() | nil
  def item_criticality(item), do: string_field(item, AgentFields.criticality())

  @spec item_evidence_requirements(map()) :: [map()]
  def item_evidence_requirements(item), do: map_list_field(item, AgentFields.evidence_requirements())

  @spec item_evidence_refs(map()) :: [map()]
  def item_evidence_refs(item), do: map_list_field(item, AgentFields.evidence_refs())

  @spec item_satisfied?(map()) :: boolean()
  def item_satisfied?(item), do: Reconciler.satisfied?(item)

  @spec evidence_kind(map()) :: String.t() | nil
  def evidence_kind(record), do: string_field(record, AgentFields.evidence_kind())

  @spec evidence_payload(map()) :: map() | nil
  def evidence_payload(record) when is_map(record) do
    case Map.get(record, AgentFields.payload()) do
      payload when is_map(payload) -> payload
      _payload -> nil
    end
  end

  def evidence_payload(_record), do: nil

  @spec evidence_observed_at(map()) :: String.t() | nil
  def evidence_observed_at(record), do: string_field(record, AgentFields.observed_at())

  defp map_list_field(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      values when is_list(values) -> Enum.filter(values, &is_map/1)
      _values -> []
    end
  end

  defp map_list_field(_map, _key), do: []

  defp string_field(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _value -> nil
    end
  end

  defp string_field(_map, _key), do: nil
end
