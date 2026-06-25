defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.OperatorInspection do
  @moduledoc """
  Operator-facing inspection packet for canonical structured execution plans.

  The inspection packet is a bounded projection. It reads canonical plan fields,
  evidence-ref metadata, gate values, rollback values, and render markers; it
  never imports Workpad Markdown or exposes raw evidence payloads.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Storage.Scrubber
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler.Freshness
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Workpad.Contract, as: WorkpadContract

  @schema "workflow.execution_plan.operator_inspection.v1"
  @max_items 100
  @max_evidence_refs 200
  @max_rejected_updates 50

  @plan_keys [
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

  @render_marker_keys [
    Fields.schema(),
    Fields.plan_id(),
    WorkpadContract.plan_revision_key(),
    Fields.tracker_kind(),
    WorkpadContract.mode_key(),
    WorkpadContract.rendered_item_count_key(),
    WorkpadContract.fingerprint_key(),
    WorkpadContract.workpad_id_key()
  ]

  @spec build(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def build(plan, opts \\ [])

  def build(plan, opts) when is_map(plan) and is_list(opts) do
    gates = Keyword.get(opts, :gates, Contract.gate_defaults())
    gate_values = gate_values(gates)
    items = Map.get(plan, Fields.items(), [])
    stale_item_ids = stale_item_ids(items)

    packet =
      %{
        "schema" => @schema,
        "plan" => Map.take(plan, @plan_keys),
        "gate_values" => gate_values,
        "gate_validation" => validate_gates(gates),
        "rollback_gate_values" => rollback_gate_values(gate_values),
        "required_item_statuses" => required_item_statuses(items, stale_item_ids),
        "evidence_refs" => evidence_ref_summaries(items),
        "freshness_state" => freshness_state(stale_item_ids),
        "latest_render_marker" => latest_render_marker(plan),
        "readiness_gate_result" => scrub_optional_map(Keyword.get(opts, :readiness_gate_result)),
        "rejected_updates" => scrub_list(Keyword.get(opts, :rejected_updates, []))
      }

    {:ok, packet}
  end

  def build(_plan, _opts) do
    {:error,
     %{
       code: "operator_inspection_invalid",
       message: "Operator inspection requires a structured execution plan object."
     }}
  end

  @spec validate_gates(term()) :: map()
  def validate_gates(gates) when is_map(gates) do
    errors =
      gate_missing_errors(gates) ++
        gate_value_errors(gates) ++
        unknown_gate_errors(gates)

    %{
      "valid" => errors == [],
      "errors" => errors
    }
  end

  def validate_gates(_gates) do
    %{
      "valid" => false,
      "errors" => [
        %{
          "code" => "invalid_gate_values",
          "path" => ["gates"],
          "message" => "Structured execution plan gates must be an object."
        }
      ]
    }
  end

  defp gate_values(gates) when is_map(gates) do
    Contract.gate_keys()
    |> Map.new(fn gate -> {gate, Map.get(gates, gate, false) == true} end)
  end

  defp gate_values(_gates), do: Contract.gate_defaults()

  defp rollback_gate_values(gates) when is_map(gates) do
    %{
      "disable_recording_gate" => rollback_gate(Contract.enabled_gate_key(), gates),
      "disable_rendering_gate" => rollback_gate(Contract.render_workpad_gate_key(), gates),
      "disable_readiness_gate" => rollback_gate(Contract.transition_readiness_required_gate_key(), gates),
      "disable_provider_adapters_gate" => rollback_gate(Contract.provider_adapters_enabled_gate_key(), gates)
    }
  end

  defp rollback_gate(gate, gates) do
    %{
      "gate" => gate,
      "current_value" => Map.get(gates, gate, false) == true,
      "rollback_value" => false
    }
  end

  defp required_item_statuses(items, stale_item_ids) do
    items
    |> Enum.filter(&operator_relevant_item?/1)
    |> Enum.take(@max_items)
    |> Enum.map(fn item ->
      evidence_refs = evidence_refs(item)
      item_id = Map.get(item, AgentFields.item_id())

      %{
        "item_id" => item_id,
        "title" => Map.get(item, AgentFields.title()),
        "status" => Map.get(item, AgentFields.status()),
        "required" => Map.get(item, AgentFields.required()) == true,
        "criticality" => Map.get(item, AgentFields.criticality()),
        "owned_by" => Map.get(item, AgentFields.owned_by()),
        "source" => Map.get(item, AgentFields.source()),
        "evidence_ref_count" => length(evidence_refs),
        "evidence_kinds" => evidence_refs |> Enum.map(&Map.get(&1, AgentFields.evidence_kind())) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        "freshness" => if(item_id in stale_item_ids, do: "stale", else: "fresh")
      }
    end)
  end

  defp operator_relevant_item?(item) when is_map(item) do
    Map.get(item, AgentFields.required()) == true or
      Contract.evidence_required_criticality?(Map.get(item, AgentFields.criticality()))
  end

  defp evidence_ref_summaries(items) do
    items
    |> Enum.flat_map(fn item ->
      item_id = Map.get(item, AgentFields.item_id())

      item
      |> evidence_refs()
      |> Enum.map(&evidence_ref_summary(item_id, &1))
    end)
    |> Enum.take(@max_evidence_refs)
  end

  defp evidence_ref_summary(item_id, ref) do
    %{
      "item_id" => item_id,
      "evidence_id" => Map.get(ref, AgentFields.evidence_id()),
      "evidence_kind" => Map.get(ref, AgentFields.evidence_kind()),
      "source" => Map.get(ref, AgentFields.source()),
      "producer" => Map.get(ref, AgentFields.producer()),
      "observed_at" => Map.get(ref, AgentFields.observed_at()),
      "payload_present" => is_map(Map.get(ref, AgentFields.payload())),
      "payload_key_count" => payload_key_count(Map.get(ref, AgentFields.payload()))
    }
  end

  defp freshness_state([]) do
    %{
      "status" => "fresh",
      "stale_item_ids" => []
    }
  end

  defp freshness_state(stale_item_ids) do
    %{
      "status" => "stale",
      "stale_item_ids" => stale_item_ids
    }
  end

  defp latest_render_marker(plan) do
    case Map.get(plan, Fields.rendering()) do
      marker when is_map(marker) -> Map.take(marker, @render_marker_keys)
      _marker -> nil
    end
  end

  defp stale_item_ids(items) when is_list(items) do
    items
    |> Enum.filter(&Freshness.stale?(&1, items))
    |> Enum.map(&Map.get(&1, AgentFields.item_id()))
    |> Enum.reject(&is_nil/1)
  end

  defp scrub_optional_map(nil), do: nil

  defp scrub_optional_map(value) when is_map(value) do
    case Scrubber.scrub_map(value) do
      {:ok, scrubbed} -> scrubbed
      {:error, reason} -> %{"redaction_error" => reason}
    end
  end

  defp scrub_optional_map(value), do: scrub_optional_map(%{"value_type" => type_name(value)})

  defp scrub_list(values) when is_list(values) do
    values
    |> Enum.take(@max_rejected_updates)
    |> Enum.map(fn
      value when is_map(value) -> scrub_optional_map(value)
      value -> %{"value_type" => type_name(value)}
    end)
  end

  defp scrub_list(_values), do: []

  defp gate_missing_errors(gates) do
    Contract.gate_keys()
    |> Enum.reject(&Map.has_key?(gates, &1))
    |> Enum.map(fn gate ->
      %{
        "code" => "missing_gate_value",
        "path" => ["gates", gate],
        "message" => "Structured execution plan gate value is missing."
      }
    end)
  end

  defp gate_value_errors(gates) do
    gates
    |> Map.take(Contract.gate_keys())
    |> Enum.reject(fn {_gate, value} -> is_boolean(value) end)
    |> Enum.map(fn {gate, _value} ->
      %{
        "code" => "invalid_gate_value",
        "path" => ["gates", gate],
        "message" => "Structured execution plan gate value must be boolean."
      }
    end)
  end

  defp unknown_gate_errors(gates) do
    gates
    |> Map.keys()
    |> Enum.reject(&(&1 in Contract.gate_keys()))
    |> Enum.map(fn gate ->
      %{
        "code" => "unknown_gate_key",
        "path" => ["gates", gate],
        "message" => "Structured execution plan gate key is not supported."
      }
    end)
  end

  defp evidence_refs(item) when is_map(item) do
    case Map.get(item, AgentFields.evidence_refs()) do
      refs when is_list(refs) -> refs
      _refs -> []
    end
  end

  defp payload_key_count(payload) when is_map(payload), do: map_size(payload)
  defp payload_key_count(_payload), do: 0

  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_atom(value), do: "atom"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "float"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(value) when is_tuple(value), do: "tuple"
  defp type_name(_value), do: "term"
end
