defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacketTemplate do
  @moduledoc """
  Builds Phase 4 review-packet fill templates from completed evidence packets.

  The template is a bounded handoff for reviewers. It validates the completed
  evidence packet first, then projects the review-packet fields that can be
  derived from the accepted evidence. It does not approve the packet, read
  evidence files, call providers, mutate workflow state, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacket
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProductionProfile.Governance

  @schema "coding_pr_delivery.production_review_packet_template.v1"
  @completed_packet_schema "coding_pr_delivery.production_review_packet.v1"
  @operator_inspection_schema "workflow.execution_plan.operator_inspection.v1"
  @required_scrubbing_boundaries [
    "structured_plan_evidence_write",
    "structured_plan_render",
    "review_packet_render"
  ]
  @authority_boundary_flags [
    "prompt_wording_authoritative",
    "workpad_markdown_authoritative",
    "raw_provider_passthrough_authorized",
    "schema_support_alone_sufficient"
  ]

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: result()
  def build(evidence_packet) when is_map(evidence_packet) do
    with {:ok, normalized_evidence_packet} <- EvidencePacket.validate(evidence_packet) do
      {:ok, template(normalized_evidence_packet)}
    end
  end

  def build(evidence_packet), do: EvidencePacket.validate(evidence_packet)

  defp template(evidence_packet) do
    claim = Map.get(evidence_packet, "production_claim", %{})
    provider_entries = Map.get(claim, "provider_matrix", [])
    governance_packets = Map.get(claim, "production_governance", [])

    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "profile_instance_id" => Map.get(evidence_packet, "profile_instance_id"),
      "template_authority" => "review_packet_shape_only",
      "does_not_read_evidence_files" => true,
      "evidence_packet" => evidence_packet,
      "review_packet_field_template" => %{
        "review_packet_id" => "fill-review-packet-id",
        "changed_source_specs" => [],
        "implementation_refs" => [],
        "deterministic_test_matrix" => [],
        "evidence_packet" => evidence_packet,
        "provider_preflight_reports" => [],
        "rollback_instructions" => rollback_instructions(provider_entries),
        "scrubbing_pipeline" => scrubbing_pipeline(governance_packets),
        "operator_inspection" => operator_inspection(provider_entries),
        "retention_policy" => retention_policy(governance_packets),
        "authority_boundaries" => authority_boundaries(),
        "owner_signoffs" => []
      },
      "fields_to_complete" => [
        "review_packet_id",
        "changed_source_specs",
        "implementation_refs",
        "deterministic_test_matrix",
        "provider_preflight_reports",
        "scrubbing_pipeline.test_results",
        "owner_signoffs"
      ]
    }
  end

  defp rollback_instructions(provider_entries) do
    %{
      "owner" => rollback_owner(provider_entries),
      "external_transition_readiness_gate" => Gates.transition_readiness_required_gate_key(),
      "legacy_review_handoff_required_mapping" => true,
      "disable_gates" => [
        Gates.transition_readiness_required_gate_key(),
        Gates.enabled_gate_key(),
        Gates.render_workpad_gate_key(),
        Gates.provider_adapters_enabled_gate_key()
      ]
    }
  end

  defp rollback_owner(provider_entries) do
    provider_entries
    |> Enum.map(&value_at(&1, ["rollback", "owner"]))
    |> first_non_empty("workflow-runtime")
  end

  defp scrubbing_pipeline(governance_packets) do
    pipelines = Enum.map(governance_packets, &value_at(&1, ["data_governance", "scrubbing_pipeline"]))
    owner = pipelines |> Enum.map(&value_at(&1, ["owner"])) |> first_non_empty("workflow-runtime-security")
    catalog = pipelines |> Enum.map(&value_at(&1, ["pattern_catalog_version"])) |> first_non_empty("fill-pattern-catalog-version")

    %{
      "owner" => owner,
      "pattern_catalog_version" => catalog,
      "pattern_catalog_rules" => scrubbing_pattern_rules(pipelines),
      "failure_behavior" => "fail_closed",
      "enforced_boundaries" => scrubbing_boundaries(pipelines),
      "test_results" => [],
      "source_provider_matrix_entry_ids" => provider_matrix_entry_ids(governance_packets)
    }
  end

  defp scrubbing_pattern_rules(pipelines) do
    pipelines
    |> Enum.flat_map(fn pipeline ->
      case value_at(pipeline, ["pattern_catalog_rules"]) do
        rules when is_list(rules) -> rules
        _missing -> []
      end
    end)
    |> Kernel.++(Governance.required_scrubbing_pattern_rules())
    |> unique_strings()
  end

  defp scrubbing_boundaries(pipelines) do
    pipelines
    |> Enum.flat_map(fn pipeline ->
      case value_at(pipeline, ["enforced_boundaries"]) do
        boundaries when is_list(boundaries) -> boundaries
        _missing -> []
      end
    end)
    |> Kernel.++(@required_scrubbing_boundaries)
    |> unique_strings()
  end

  defp operator_inspection(provider_entries) do
    %{
      "schema" => @operator_inspection_schema,
      "gate_values" => first_gate_values(provider_entries),
      "candidate_gate_values_by_entry" => gate_values_by_entry(provider_entries),
      "contains_raw_evidence_payload" => false,
      "workpad_markdown_authoritative" => false
    }
  end

  defp first_gate_values(provider_entries) do
    provider_entries
    |> Enum.map(&value_at(&1, ["structured_plan_gates"]))
    |> Enum.find(&is_map/1)
    |> case do
      nil -> %{Gates.transition_readiness_required_gate_key() => false}
      gates -> gates
    end
  end

  defp gate_values_by_entry(provider_entries) do
    Enum.map(provider_entries, fn entry ->
      %{
        "provider_matrix_entry_id" => Map.get(entry, "id"),
        "gate_values" => Map.get(entry, "structured_plan_gates", %{})
      }
    end)
  end

  defp retention_policy(governance_packets) do
    governance = Enum.find(governance_packets, &is_map/1) || %{}
    data_governance = value_at(governance, ["data_governance"]) || %{}

    %{
      "retention_class" => value_at(data_governance, ["retention_class"]) || "fill-retention-class",
      "retention_period_days" => value_at(data_governance, ["retention_period_days"]) || 1,
      "cleanup_owner" => value_at(data_governance, ["cleanup_owner"]) || "workflow-runtime",
      "tombstone_preserving" => value_at(data_governance, ["tombstone", "preserves_audit_trail"]) == true,
      "source_provider_matrix_entry_ids" => provider_matrix_entry_ids(governance_packets)
    }
  end

  defp authority_boundaries do
    Map.new(@authority_boundary_flags, &{&1, false})
  end

  defp provider_matrix_entry_ids(governance_packets) do
    governance_packets
    |> Enum.map(&value_at(&1, ["provider_matrix_entry_id"]))
    |> unique_strings()
  end

  defp first_non_empty(values, default) do
    Enum.find(values, default, &non_empty_string?/1)
  end

  defp unique_strings(values) do
    values
    |> Enum.filter(&non_empty_string?/1)
    |> Enum.uniq()
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      cond do
        is_map(current) and Map.has_key?(current, key) ->
          {:cont, Map.get(current, key)}

        is_map(current) and is_atom(key) and Map.has_key?(current, Atom.to_string(key)) ->
          {:cont, Map.get(current, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil
end
