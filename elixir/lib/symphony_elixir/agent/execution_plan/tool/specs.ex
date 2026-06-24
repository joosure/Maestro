defmodule SymphonyElixir.Agent.ExecutionPlan.Tool.Specs do
  @moduledoc """
  Dynamic Tool spec builder for generic Agent execution-plan tools.

  `Tool.Contract` owns stable machine keys and values. This module owns the
  external Dynamic Tool presentation schema, including JSON Schema fragments and
  operator-facing descriptions.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Spec}
  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Tool.Contract

  @schema_type_key "type"
  @schema_additional_properties_key "additionalProperties"
  @schema_properties_key "properties"
  @schema_required_key "required"
  @schema_items_key "items"
  @schema_description_key "description"

  @schema_object "object"
  @schema_string "string"
  @schema_integer "integer"
  @schema_array "array"
  @schema_null "null"

  @schema_version Metadata.Contract.default_schema_version()

  @metadata_schema_version_key Metadata.Contract.schema_version()
  @metadata_side_effect_key Metadata.Contract.side_effect()
  @metadata_risk_flags_key Metadata.Contract.risk_flags()
  @metadata_capability_key Metadata.Contract.capability()
  @metadata_source_kind_key Metadata.Contract.source_kind()
  @metadata_operator_only_key Metadata.Contract.operator_only()
  @tool_name_key Spec.name_key()
  @tool_description_key Spec.description_key()
  @tool_input_schema_key Spec.input_schema_key()

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      snapshot_spec(),
      upsert_spec(),
      update_item_spec(),
      append_evidence_spec()
    ]
  end

  defp snapshot_spec do
    tool_spec(
      Contract.snapshot_tool(),
      Contract.snapshot_capability(),
      "Read a bounded generic Agent execution plan summary.",
      Metadata.Contract.read_only_side_effect(),
      [],
      object_schema(
        %{
          Fields.plan_id() => string_property("Agent execution plan id.")
        },
        required: [Fields.plan_id()]
      )
    )
  end

  defp upsert_spec do
    tool_spec(
      Contract.upsert_tool(),
      Contract.upsert_capability(),
      "Create a generic Agent plan or merge agent-draft informational items into an existing plan.",
      Metadata.Contract.write_side_effect(),
      Contract.write_risk_flags(),
      object_schema(%{
        Contract.plan_arg() => nullable_object_property("Full agent.execution_plan.v1 record for creation."),
        Fields.plan_id() => nullable_string_property("Existing Agent execution plan id."),
        Contract.plan_revision_arg() => nullable_integer_property("Caller-observed plan revision for item merge."),
        Fields.items() => nullable_array_property(object_type(), "Agent-owned informational items.")
      })
    )
  end

  defp update_item_spec do
    tool_spec(
      Contract.update_item_tool(),
      Contract.update_item_capability(),
      "Request an agent-owned execution plan item status update with optimistic concurrency.",
      Metadata.Contract.write_side_effect(),
      Contract.write_risk_flags(),
      object_schema(
        %{
          Fields.plan_id() => string_property("Agent execution plan id."),
          Fields.item_id() => string_property("Agent execution plan item id."),
          Fields.status() => string_property("Requested item status."),
          Contract.plan_revision_arg() => integer_property("Caller-observed plan revision.")
        },
        required: [Fields.plan_id(), Fields.item_id(), Fields.status(), Contract.plan_revision_arg()]
      )
    )
  end

  defp append_evidence_spec do
    tool_spec(
      Contract.append_evidence_tool(),
      Contract.append_evidence_capability(),
      "Append an immutable generic evidence reference to an Agent execution plan item.",
      Metadata.Contract.write_side_effect(),
      Contract.write_risk_flags(),
      object_schema(
        %{
          Fields.plan_id() => string_property("Agent execution plan id."),
          Fields.item_id() => string_property("Agent execution plan item id."),
          Contract.evidence_ref_arg() => object_property("Generic immutable evidence ref."),
          Contract.plan_revision_arg() => integer_property("Caller-observed plan revision.")
        },
        required: [Fields.plan_id(), Fields.item_id(), Contract.evidence_ref_arg(), Contract.plan_revision_arg()]
      )
    )
  end

  defp object_schema(properties, opts \\ []) when is_map(properties) do
    %{
      @schema_type_key => @schema_object,
      @schema_additional_properties_key => false,
      @schema_properties_key => properties
    }
    |> maybe_put(@schema_required_key, Keyword.get(opts, :required))
  end

  defp object_type, do: %{@schema_type_key => @schema_object}

  defp string_property(description), do: typed_property(@schema_string, description)
  defp integer_property(description), do: typed_property(@schema_integer, description)
  defp object_property(description), do: typed_property(@schema_object, description)
  defp nullable_string_property(description), do: typed_property([@schema_string, @schema_null], description)
  defp nullable_integer_property(description), do: typed_property([@schema_integer, @schema_null], description)
  defp nullable_object_property(description), do: typed_property([@schema_object, @schema_null], description)

  defp nullable_array_property(item_schema, description) do
    [@schema_array, @schema_null]
    |> typed_property(description)
    |> Map.put(@schema_items_key, item_schema)
  end

  defp typed_property(type, description) do
    %{
      @schema_type_key => type,
      @schema_description_key => description
    }
  end

  defp tool_spec(name, capability, description, side_effect, risk_flags, input_schema) do
    %{
      @tool_name_key => name,
      @tool_description_key => description,
      @tool_input_schema_key => input_schema,
      @metadata_schema_version_key => @schema_version,
      @metadata_side_effect_key => side_effect,
      @metadata_risk_flags_key => risk_flags,
      @metadata_capability_key => capability,
      @metadata_source_kind_key => Contract.source_kind(),
      @metadata_operator_only_key => true
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
