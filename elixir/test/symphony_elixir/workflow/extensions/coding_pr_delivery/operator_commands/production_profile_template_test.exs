defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.ProductionProfileTemplateTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.OperatorCommands.{
    ProductionProfilePlan,
    ProductionProfileTemplate,
    ProductionProfileValidate
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    EvidencePacketTemplate,
    Phase2ClaimTemplate,
    Phase2EvidencePlan,
    ReviewDecision,
    ReviewPacketTemplate
  }

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "is registered as a Coding PR Delivery operator command" do
    assert ProductionProfileTemplate in CodingPrDelivery.operator_commands()
  end

  test "builds an evidence packet template from claim metadata without provider side effects" do
    assert {:ok, claim} = Phase2ClaimTemplate.build(:linear_cnb_shadow, shadow_run_id: "template-shadow-1")
    claim = Map.put(claim, "raw_payload", "secret-template-payload")

    with_json_file!(claim, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate(["--kind", "evidence_packet_template", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["schema"] == "coding_pr_delivery.production_profile_template_result.v1"
      assert payload["kind"] == "evidence_packet_template"
      assert payload["status"] == "ready"
      assert payload["valid"] == true
      assert payload["template_schema"] == "coding_pr_delivery.production_evidence_packet_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.production_evidence_packet.v1"
      assert payload["does_not_collect_live_evidence"] == true
      assert payload["does_not_read_referenced_evidence_files"] == true
      assert payload["does_not_call_providers"] == true
      assert payload["does_not_mutate_workflow_state"] == true
      assert payload["does_not_enable_production"] == true

      template = payload["template"]
      assert template["template_authority"] == "evidence_packet_shape_only"
      assert template["does_not_collect_live_evidence"] == true
      assert [%{"provider_matrix_entry_id" => "linear-cnb-shadow"} | _rest] = template["scenario_evidence_requirements"]
      refute stdout =~ "secret-template-payload"
    end)
  end

  test "builds preflight report templates from Phase 2 evidence plans" do
    assert {:ok, phase2_plan} =
             Phase2EvidencePlan.build(:tiered_reference,
               tapd_cnb_shadow_run_id: "template-command-tapd-cnb",
               linear_cnb_shadow_run_id: "template-command-linear-cnb"
             )

    phase2_plan = Map.put(phase2_plan, "raw_payload", "raw command input")

    with_json_file!(phase2_plan, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate(["--kind", "preflight_report_template", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["schema"] == "coding_pr_delivery.production_profile_template_result.v1"
      assert payload["kind"] == "preflight_report_template"
      assert payload["status"] == "ready"
      assert payload["valid"] == true
      assert payload["template_schema"] == "coding_pr_delivery.provider_preflight_report_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.provider_preflight_report.v1"
      assert payload["does_not_collect_live_evidence"] == true
      assert payload["does_not_call_providers"] == true
      assert payload["does_not_enable_production"] == true

      template = payload["template"]
      assert template["template_authority"] == "preflight_report_shape_only"
      assert length(template["preflight_result_requirements"]) == 6
      refute stdout =~ "raw command input"
    end)
  end

  test "builds review packet templates from completed evidence metadata" do
    with_json_file!(completed_evidence_packet(:linear_cnb_shadow, "review-template-shadow-1"), fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate(["--kind", "review_packet_template", "--file", path, "--pretty"])

      payload = Jason.decode!(stdout)

      assert payload["kind"] == "review_packet_template"
      assert payload["template_schema"] == "coding_pr_delivery.production_review_packet_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.production_review_packet.v1"
      assert payload["template"]["does_not_read_evidence_files"] == true

      inspection = payload["template"]["review_packet_field_template"]["operator_inspection"]
      assert inspection["contains_raw_evidence_payload"] == false
      assert inspection["workpad_markdown_authoritative"] == false
    end)
  end

  test "builds enablement request templates with selected provider scope options" do
    with_json_file!(ready_review_decision(:linear_cnb_shadow, "enablement-template-shadow-1"), fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate([
                 "--kind",
                 "enablement_request_template",
                 "--file",
                 path,
                 "--provider-matrix-entry-id",
                 "linear-cnb-shadow",
                 "--repository",
                 "acme/widgets",
                 "--observation-days",
                 "21",
                 "--json"
               ])

      payload = Jason.decode!(stdout)
      field_template = payload["template"]["enablement_request_field_template"]

      assert payload["template_schema"] == "coding_pr_delivery.production_enablement_request_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.production_enablement_request.v1"
      assert field_template["scope"]["provider_matrix_entry_ids"] == ["linear-cnb-shadow"]
      assert field_template["scope"]["repositories"] == ["acme/widgets"]
      assert field_template["observation_window"]["duration_days"] == 21
      assert field_template["activation_control"]["requires_operator_apply"] == true
      assert field_template["activation_control"]["applies_immediately"] == false
    end)
  end

  test "builds operator apply and observation status templates" do
    apply_plan = ready_operator_apply_plan()

    with_json_file!(apply_plan, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate(["--kind", "operator_apply_record_template", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["template_schema"] == "coding_pr_delivery.production_operator_apply_record_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.production_operator_apply_record.v1"
      assert payload["template"]["template_authority"] == "operator_apply_record_shape_only"
    end)

    apply_record = accepted_operator_apply_record(apply_plan)

    with_json_file!(apply_record, fn path ->
      assert {stdout, "", 0} =
               ProductionProfileTemplate.evaluate(["--kind", "observation_status_template", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["template_schema"] == "coding_pr_delivery.production_observation_status_template.v1"
      assert payload["completed_packet_schema"] == "coding_pr_delivery.production_observation_status.v1"
      assert payload["template"]["records_observation_only"] == true
      assert payload["template"]["does_not_enable_production"] == true
      assert payload["template"]["allowed_evidence_ref_prefixes"] == ["evidence/", "https://", "http://"]

      criteria_results = get_in(payload, ["template", "observation_status_field_template", "criteria_results"])
      assert Enum.all?(criteria_results, &(List.first(&1["evidence_files"]) =~ "evidence/observation/"))
    end)
  end

  test "returns template validation errors without echoing raw packet fields" do
    with_json_file!(%{"profile_instance_id" => "secret-profile"}, fn path ->
      assert {stdout, "", 1} =
               ProductionProfileTemplate.evaluate(["--kind", "evidence_packet_template", "--file", path, "--json"])

      payload = Jason.decode!(stdout)

      assert payload["kind"] == "evidence_packet_template"
      assert payload["status"] == "invalid"
      assert payload["valid"] == false
      assert payload["errors"] != []
      assert payload["template"] == nil
      refute stdout =~ "secret-profile"
    end)
  end

  test "does not echo unknown kinds, invalid JSON, unexpected args, or invalid deps" do
    with_json_file!(%{}, fn path ->
      assert {"", unknown_stderr, 64} =
               ProductionProfileTemplate.evaluate(["--kind", "secret-kind", "--file", path])

      assert unknown_stderr =~ "Unsupported template kind"
      refute unknown_stderr =~ "secret-kind"
    end)

    unique = System.unique_integer([:positive, :monotonic])
    path = Path.join(System.tmp_dir!(), "secret-template-packet-#{unique}.json")
    File.write!(path, "{secret-template-json")

    try do
      assert {"", invalid_json_stderr, 64} =
               ProductionProfileTemplate.evaluate(["--kind", "evidence_packet_template", "--file", path])

      assert invalid_json_stderr =~ "Unable to read or parse metadata JSON file"
      refute invalid_json_stderr =~ path
      refute invalid_json_stderr =~ "secret-template-json"
    after
      File.rm(path)
    end

    assert {"", unexpected_stderr, 64} =
             ProductionProfileTemplate.evaluate(["--kind", "evidence_packet_template", "--file", "packet.json", "secret-extra"])

    assert unexpected_stderr =~ "Unexpected argument count: 1"
    refute unexpected_stderr =~ "secret-extra"

    assert {"", deps_stderr, 70} = ProductionProfileTemplate.evaluate([], deps: %{secret: true})

    assert deps_stderr =~ "reason=dependency_invalid"
    assert deps_stderr =~ "value_type=nil"
    refute deps_stderr =~ "secret"
  end

  test "command ids stay distinct" do
    assert ProductionProfileTemplate.id() != ProductionProfilePlan.id()
    assert ProductionProfileTemplate.id() != ProductionProfileValidate.id()
  end

  defp ready_review_decision(template, shadow_run_id) do
    entry_id = entry_id(template)

    assert {:ok, review_packet_template} =
             ReviewPacketTemplate.build(completed_evidence_packet(template, shadow_run_id))

    review_packet =
      review_packet_template["review_packet_field_template"]
      |> complete_review_packet(entry_id, template, shadow_run_id)

    assert {:ok, decision} = ReviewDecision.build(review_packet)
    decision
  end

  defp ready_operator_apply_plan do
    %{
      "schema" => "coding_pr_delivery.production_operator_apply_plan.v1",
      "status" => "ready_for_operator_apply",
      "enablement_request_id" => "enablement-linear-cnb-shadow",
      "profile_instance_id" => "coding-pr-delivery-production",
      "review_packet_id" => "review-packet-linear-cnb-shadow",
      "scope" => %{
        "environment" => "production",
        "repositories" => ["acme/widgets"],
        "provider_matrix_entry_ids" => ["linear-cnb-shadow"],
        "side_effect_mode" => "shadow_no_write"
      },
      "gate_values" => %{
        Gates.transition_readiness_required_gate_key() => false,
        Gates.enabled_gate_key() => true
      },
      "observation_window" => %{
        "duration_days" => 14,
        "success_criteria" => ["zero canonical writes", "zero shadow isolation violations"]
      },
      "activation_control" => %{
        "change_ticket" => "CHANGE-123",
        "requires_operator_apply" => true,
        "applies_immediately" => false
      },
      "operator_steps" => [
        %{
          "id" => "confirm_change_ticket",
          "title" => "Confirm change ticket and operator ownership.",
          "status" => "pending_operator_apply",
          "change_ticket" => "CHANGE-123"
        },
        %{
          "id" => "apply_gate_values",
          "title" => "Apply reviewed gate values through the production configuration path.",
          "status" => "pending_operator_apply",
          "gate_values" => %{
            Gates.transition_readiness_required_gate_key() => false,
            Gates.enabled_gate_key() => true
          }
        }
      ],
      "rollback_steps" => [
        %{
          "id" => "disable_transition_readiness",
          "title" => "Disable the external transition readiness gate if rollback is needed.",
          "status" => "available_before_apply",
          "gate" => Gates.transition_readiness_required_gate_key(),
          "owner" => "workflow-runtime"
        },
        %{
          "id" => "disable_configured_gates",
          "title" => "Disable every reviewed rollback gate.",
          "status" => "available_before_apply",
          "disable_gates" => [
            Gates.transition_readiness_required_gate_key(),
            Gates.enabled_gate_key()
          ]
        }
      ],
      "blockers" => [],
      "does_not_apply_settings" => true,
      "requires_operator_confirmation" => true,
      "can_apply_automatically" => false
    }
  end

  defp accepted_operator_apply_record(apply_plan) do
    steps =
      apply_plan
      |> Map.get("operator_steps", [])
      |> Enum.map(
        &%{
          "id" => Map.get(&1, "id"),
          "status" => "completed",
          "completed_by" => "release-manager",
          "completed_at" => "2026-06-25T00:00:00Z"
        }
      )

    %{
      "apply_record_id" => "apply-record-linear-cnb-shadow",
      "operator_apply_plan" => apply_plan,
      "apply_metadata" => %{
        "applied_by" => "release-manager",
        "applied_at" => "2026-06-25T00:00:00Z",
        "change_ticket" => "CHANGE-123",
        "operator_confirmation" => true,
        "automatic_apply" => false
      },
      "applied_scope" => Map.fetch!(apply_plan, "scope"),
      "applied_gate_values" => Map.fetch!(apply_plan, "gate_values"),
      "completed_operator_steps" => steps,
      "rollback_readiness" => %{
        "owner" => "workflow-runtime",
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key()
        ],
        "verified" => true,
        "verified_by" => "release-manager"
      },
      "observation_start" => %{
        "started" => true,
        "observation_window" => Map.fetch!(apply_plan, "observation_window")
      }
    }
  end

  defp complete_review_packet(field_template, entry_id, template, shadow_run_id) do
    field_template
    |> Map.merge(%{
      "review_packet_id" => "review-packet-#{entry_id}",
      "changed_source_specs" => [
        "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
        "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md"
      ],
      "implementation_refs" => [
        "commit:0cb37c9",
        "local-patch:coding-pr-delivery-template-command"
      ],
      "deterministic_test_matrix" => [
        %{"command" => "mise exec -- mix test test/symphony_elixir/workflow/extensions/coding_pr_delivery/production_profile", "status" => "passed"}
      ],
      "provider_preflight_reports" => [passed_preflight_report(template, shadow_run_id)],
      "owner_signoffs" => [owner_signoff()]
    })
    |> put_in(["scrubbing_pipeline", "test_results"], [
      %{"name" => "scrubber evidence boundaries", "status" => "passed"}
    ])
  end

  defp passed_preflight_report(:tapd_cnb_shadow, shadow_run_id) do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:tapd_cnb_shadow, tapd_cnb_shadow_run_id: shadow_run_id)
    preflight_report(phase2_plan)
  end

  defp passed_preflight_report(:linear_cnb_shadow, shadow_run_id) do
    assert {:ok, phase2_plan} = Phase2EvidencePlan.build(:linear_cnb_shadow, linear_cnb_shadow_run_id: shadow_run_id)
    preflight_report(phase2_plan)
  end

  defp preflight_report(phase2_plan) do
    %{
      "schema" => "coding_pr_delivery.provider_preflight_report.v1",
      "phase2_evidence_plan" => phase2_plan,
      "provider_preflight_results" => preflight_results(phase2_plan),
      "explicit_non_claims" => [
        "preflight_report_does_not_collect_live_provider_evidence",
        "preflight_report_does_not_enable_production"
      ]
    }
  end

  defp preflight_results(phase2_plan) do
    phase2_plan
    |> Map.fetch!("provider_plans")
    |> Enum.flat_map(fn provider_plan ->
      template = Map.fetch!(provider_plan, "template")

      provider_plan
      |> get_in(["read_only_preflight", "commands"])
      |> Enum.map(&preflight_result(template, &1))
    end)
  end

  defp preflight_result(template, command) do
    %{
      "template" => template,
      "command_id" => Map.fetch!(command, "id"),
      "target" => Map.fetch!(command, "target"),
      "provider_kind" => Map.fetch!(command, "provider_kind"),
      "status" => "passed",
      "ran_at" => "2026-06-25T00:00:00Z",
      "side_effect_mode" => "read_only",
      "write_performed" => false,
      "production_enabled" => false,
      "evidence_files" => ["evidence/preflight/#{template}/#{Map.fetch!(command, "id")}.md"]
    }
  end

  defp completed_evidence_packet(template, shadow_run_id) do
    assert {:ok, claim} = Phase2ClaimTemplate.build(template, shadow_run_id: shadow_run_id)
    assert {:ok, template} = EvidencePacketTemplate.build(claim)

    %{
      "production_claim" => claim,
      "scenario_evidence" => Enum.map(template["scenario_evidence_requirements"], &complete_scenario_evidence/1),
      "non_claim_acknowledgements" => Enum.map(template["non_claim_acknowledgement_requirements"], &complete_non_claim_acknowledgement/1)
    }
  end

  defp complete_scenario_evidence(requirement) do
    evidence =
      %{
        "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
        "scenario_id" => requirement["scenario_id"],
        "status" => requirement["required_status"],
        "evidence_kind" => requirement["required_evidence_kind"],
        "collector" => "provider-integration-owner",
        "collected_at" => "2026-06-25T00:00:00Z",
        "evidence_files" => requirement["evidence_files"]
      }

    if is_map(requirement["shadow"]) do
      evidence
      |> Map.merge(requirement["no_write_flags"])
      |> Map.put("shadow", requirement["shadow"])
    else
      evidence
    end
  end

  defp complete_non_claim_acknowledgement(requirement) do
    %{
      "provider_matrix_entry_id" => requirement["provider_matrix_entry_id"],
      "non_claims" => requirement["non_claims"],
      "owner" => "provider-integration-owner",
      "acknowledged_at" => "2026-06-25T00:00:00Z"
    }
  end

  defp owner_signoff do
    %{
      "role" => "workflow-runtime-owner",
      "owner" => "workflow-runtime",
      "decision" => "approved",
      "approved_at" => "2026-06-25T00:00:00Z"
    }
  end

  defp entry_id(:linear_cnb_shadow), do: "linear-cnb-shadow"
  defp entry_id(:tapd_cnb_shadow), do: "tapd-cnb-shadow"

  defp with_json_file!(payload, fun) do
    unique = System.unique_integer([:positive, :monotonic])
    path = Path.join(System.tmp_dir!(), "production-profile-template-packet-#{unique}.json")
    File.write!(path, Jason.encode!(payload))

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end
end
