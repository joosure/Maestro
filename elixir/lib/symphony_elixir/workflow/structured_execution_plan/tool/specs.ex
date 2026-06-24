defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Specs do
  @moduledoc """
  Dynamic Tool spec builder for workflow structured execution-plan tools.

  `Tool.Contract` owns stable machine keys and values. This module owns the
  external Dynamic Tool presentation schema, including JSON Schema fragments and
  operator-facing descriptions.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Spec}
  alias SymphonyElixir.Agent.ExecutionPlan.Fields, as: AgentFields
  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract

  @schema_type_key "type"
  @schema_additional_properties_key "additionalProperties"
  @schema_properties_key "properties"
  @schema_required_key "required"
  @schema_items_key "items"
  @schema_description_key "description"
  @schema_enum_key "enum"

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

  @snapshot_capability CapabilityNames.workflow_plan_snapshot()
  @upsert_capability CapabilityNames.workflow_plan_upsert()
  @update_item_capability CapabilityNames.workflow_plan_update_item()
  @render_workpad_capability CapabilityNames.workflow_plan_render_workpad()

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      snapshot_spec(),
      upsert_spec(),
      update_item_spec(),
      render_workpad_spec()
    ]
  end

  defp snapshot_spec do
    tool_spec(
      Contract.snapshot_tool(),
      @snapshot_capability,
      "Read a bounded canonical structured execution plan summary.",
      Metadata.Contract.read_only_side_effect(),
      [],
      object_schema(%{
        Fields.plan_id() => nullable_string_property("Structured plan id."),
        Fields.run_id() => nullable_string_property("Run id used with workflow_profile and route_key."),
        Fields.workflow_profile() => nullable_object_property("Workflow profile identity."),
        Fields.route_key() => nullable_string_property("Workflow route key.")
      })
    )
  end

  defp upsert_spec do
    tool_spec(
      Contract.upsert_tool(),
      @upsert_capability,
      "Create a canonical plan or merge agent-owned informational items into an existing plan.",
      Metadata.Contract.write_side_effect(),
      Contract.write_risk_flags(),
      object_schema(%{
        Contract.plan_arg() => nullable_object_property("Full canonical plan record for creation."),
        Fields.plan_id() => nullable_string_property("Existing structured plan id."),
        Contract.plan_revision_arg() => nullable_integer_property("Caller-observed plan revision for item merge."),
        Fields.items() => nullable_array_property(object_type(), "Agent-owned informational items.")
      })
    )
  end

  defp update_item_spec do
    tool_spec(
      Contract.update_item_tool(),
      @update_item_capability,
      "Request a structured plan item status update with optimistic concurrency.",
      Metadata.Contract.write_side_effect(),
      Contract.write_risk_flags(),
      object_schema(
        %{
          Fields.plan_id() => string_property("Structured plan id."),
          AgentFields.item_id() => string_property("Structured plan item id."),
          AgentFields.status() => string_property("Requested item status."),
          Contract.plan_revision_arg() => integer_property("Caller-observed plan revision."),
          Contract.note_arg() => nullable_string_property("Optional bounded agent note."),
          Contract.evidence_id_arg() => nullable_string_property("Optional evidence id reference.")
        },
        required: [Fields.plan_id(), AgentFields.item_id(), AgentFields.status(), Contract.plan_revision_arg()]
      )
    )
  end

  defp render_workpad_spec do
    tool_spec(
      Contract.render_workpad_tool(),
      @render_workpad_capability,
      "Render a preview Workpad from the canonical structured execution plan without changing authoritative plan facts.",
      Metadata.Contract.read_only_side_effect(),
      [],
      object_schema(
        %{
          Fields.plan_id() => string_property("Structured plan id."),
          Contract.plan_revision_arg() => integer_property("Caller-observed plan revision."),
          Contract.mode_arg() => enum_property([Contract.preview_mode()], "Render mode. Only preview is enabled in this phase."),
          Contract.heading_arg() => nullable_string_property("Optional Workpad heading override."),
          Contract.max_items_arg() => nullable_integer_property("Optional bounded item limit for preview rendering.")
        },
        required: [Fields.plan_id(), Contract.plan_revision_arg(), Contract.mode_arg()]
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
  defp nullable_string_property(description), do: typed_property([@schema_string, @schema_null], description)
  defp nullable_integer_property(description), do: typed_property([@schema_integer, @schema_null], description)
  defp nullable_object_property(description), do: typed_property([@schema_object, @schema_null], description)

  defp nullable_array_property(item_schema, description) do
    [@schema_array, @schema_null]
    |> typed_property(description)
    |> Map.put(@schema_items_key, item_schema)
  end

  defp enum_property(values, description) when is_list(values) do
    @schema_string
    |> typed_property(description)
    |> Map.put(@schema_enum_key, values)
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
