defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase4ReviewPlan do
  @moduledoc """
  Builds bounded Phase 4 review plans from Phase 2 evidence plans.

  The plan summarizes what reviewers can prepare before live provider evidence
  exists and why the production decision remains blocked. It does not complete
  evidence, read evidence files, call providers, mutate workflow state, approve
  production, or enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.phase4_review_plan.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @error_code "coding_pr_delivery_phase4_review_plan_invalid"
  @required_scrubbing_boundaries [
    "structured_plan_evidence_write",
    "structured_plan_render",
    "review_packet_render"
  ]
  @required_authority_boundaries [
    "prompt_wording_authoritative",
    "workpad_markdown_authoritative",
    "raw_provider_passthrough_authorized",
    "schema_support_alone_sufficient"
  ]
  @source_specs [
    "specs/workflow/profiles/coding_pr_delivery/profile_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/typed_workflow_tools/conformance_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/review_handoff_readiness_policy/conformance_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/reconciliation/conformance_spec.md",
    "specs/workflow/extensions/coding_pr_delivery/reconciliation/production_profile_spec.md",
    "specs/workflow/execution_plan_adoption/readiness_spec.md",
    "specs/workflow/execution_plan_adoption/production_profile_spec.md"
  ]

  @type input :: Phase2EvidencePlan.plan() | String.t() | map()
  @type result :: {:ok, map()} | {:error, map()}

  @spec build(input(), keyword()) :: result()
  def build(input, opts \\ [])

  def build(input, opts) when is_list(opts) do
    with {:ok, phase2_plan} <- phase2_plan(input, opts),
         :ok <- validate_phase2_plan(phase2_plan) do
      {:ok, review_plan(phase2_plan, opts)}
    end
  end

  def build(_input, _opts) do
    {:error, invalid([issue("invalid_options", [], "Phase 4 review plan options must be a keyword list.")])}
  end

  defp phase2_plan(%{"schema" => @phase2_schema} = plan, _opts), do: {:ok, plan}
  defp phase2_plan(plan, opts), do: Phase2EvidencePlan.build(plan, opts)

  defp validate_phase2_plan(plan) do
    provider_plans = Map.get(plan, "provider_plans")

    cond do
      Map.get(plan, "schema") != @phase2_schema ->
        {:error,
         invalid([
           issue("invalid_phase2_schema", ["phase2_plan", "schema"], "Phase 4 review plans require a Phase 2 evidence plan.")
         ])}

      not is_list(provider_plans) or provider_plans == [] ->
        {:error,
         invalid([
           issue("missing_provider_plans", ["phase2_plan", "provider_plans"], "Phase 2 evidence plan must include provider plans.")
         ])}

      true ->
        :ok
    end
  end

  defp review_plan(phase2_plan, opts) do
    provider_review_plans = phase2_plan |> Map.get("provider_plans", []) |> Enum.map(&provider_review_plan/1)

    %{
      "schema" => @schema,
      "plan_id" => Keyword.get(opts, :plan_id, default_plan_id(phase2_plan)),
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "review_authority" => "phase4_review_planning_only",
      "phase4_ready" => false,
      "review_decision_status" => "blocked",
      "does_not_collect_live_evidence" => true,
      "does_not_read_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true,
      "provider_review_plans" => provider_review_plans,
      "review_packet_requirements" => review_packet_requirements(provider_review_plans),
      "blocking_requirements" => blocking_requirements(provider_review_plans),
      "explicit_non_claims" => explicit_non_claims()
    }
  end

  defp default_plan_id(phase2_plan) do
    phase2_id = Map.get(phase2_plan, "plan_id") || "coding_pr_delivery.phase2.unknown"
    "#{phase2_id}.phase4_review"
  end

  defp provider_review_plan(provider_plan) do
    evidence_template = Map.get(provider_plan, "evidence_packet_template", %{})
    requirements = Map.get(evidence_template, "scenario_evidence_requirements", [])
    provider_entry_ids = Map.get(provider_plan, "provider_matrix_entry_ids", [])

    %{
      "tier" => Map.get(provider_plan, "tier"),
      "template" => Map.get(provider_plan, "template"),
      "provider_matrix_entry_ids" => provider_entry_ids,
      "tracker_kinds" => Map.get(provider_plan, "tracker_kinds", []),
      "repo_provider_kinds" => Map.get(provider_plan, "repo_provider_kinds", []),
      "side_effect_modes" => Map.get(provider_plan, "side_effect_modes", []),
      "live_evidence_status" => Map.get(provider_plan, "live_evidence_status", "not_collected"),
      "scenario_count" => Map.get(provider_plan, "scenario_count", 0),
      "required_evidence_kinds" => required_evidence_kinds(requirements),
      "required_evidence_files" => required_evidence_files(requirements),
      "shadow" => shadow_summary(requirements),
      "non_claims" => non_claims(provider_plan),
      "review_packet_blocked_until_completed_evidence" => true,
      "evidence_packet_required_before_review" => true
    }
  end

  defp required_evidence_kinds(requirements) do
    requirements
    |> Enum.map(&Map.get(&1, "required_evidence_kind"))
    |> unique_strings()
  end

  defp required_evidence_files(requirements) do
    requirements
    |> Enum.flat_map(fn requirement ->
      case Map.get(requirement, "evidence_files") do
        files when is_list(files) -> files
        _missing -> []
      end
    end)
    |> unique_strings()
  end

  defp shadow_summary(requirements) do
    requirements
    |> Enum.map(&Map.get(&1, "shadow"))
    |> Enum.find(&is_map/1)
    |> case do
      nil ->
        nil

      shadow ->
        %{
          "prefix" => Map.get(shadow, "prefix"),
          "run_id" => Map.get(shadow, "run_id"),
          "authority" => Map.get(shadow, "authority"),
          "canonical_authority" => Map.get(shadow, "canonical_authority"),
          "allowed_destinations" => Map.get(shadow, "allowed_destinations", [])
        }
    end
  end

  defp non_claims(provider_plan) do
    provider_plan
    |> Map.get("evidence_runbook", %{})
    |> Map.get("entries", [])
    |> Enum.flat_map(&Map.get(&1, "non_claims", []))
    |> unique_strings()
  end

  defp review_packet_requirements(provider_review_plans) do
    %{
      "changed_source_specs" => @source_specs,
      "implementation_refs" => ["fill-implementation-pr-or-local-patch-ref"],
      "deterministic_test_matrix" => ["fill-deterministic-test-matrix"],
      "completed_evidence_packets" => completed_evidence_packets(provider_review_plans),
      "rollback_instructions" => %{
        "external_transition_readiness_gate" => Gates.transition_readiness_required_gate_key(),
        "legacy_review_handoff_required_mapping" => true,
        "disable_gates" => [
          Gates.transition_readiness_required_gate_key(),
          Gates.enabled_gate_key(),
          Gates.render_workpad_gate_key(),
          Gates.provider_adapters_enabled_gate_key()
        ]
      },
      "scrubbing_pipeline" => %{
        "failure_behavior" => "fail_closed",
        "required_boundaries" => @required_scrubbing_boundaries,
        "test_results" => "fill-scrubbing-test-results"
      },
      "operator_inspection" => %{
        "contains_raw_evidence_payload" => false,
        "workpad_markdown_authoritative" => false,
        "requires_bounded_evidence_summaries" => true
      },
      "retention_policy" => [
        "fill-retention-class",
        "fill-retention-period-days",
        "fill-cleanup-owner",
        "prove-tombstone-preserving-cleanup"
      ],
      "authority_boundaries" => Map.new(@required_authority_boundaries, &{&1, false}),
      "owner_signoffs" => ["fill-owner-signoffs"]
    }
  end

  defp completed_evidence_packets(provider_review_plans) do
    Enum.map(provider_review_plans, fn plan ->
      %{
        "template" => Map.get(plan, "template"),
        "provider_matrix_entry_ids" => Map.get(plan, "provider_matrix_entry_ids", []),
        "required_evidence_kinds" => Map.get(plan, "required_evidence_kinds", []),
        "required_evidence_files" => Map.get(plan, "required_evidence_files", []),
        "scenario_count" => Map.get(plan, "scenario_count", 0),
        "live_evidence_status" => Map.get(plan, "live_evidence_status")
      }
    end)
  end

  defp blocking_requirements(provider_review_plans) do
    evidence_blockers =
      Enum.map(provider_review_plans, fn plan ->
        %{
          "code" => "completed_evidence_packet_required",
          "template" => Map.get(plan, "template"),
          "provider_matrix_entry_ids" => Map.get(plan, "provider_matrix_entry_ids", []),
          "message" => "Completed provider evidence packet is required before Phase 4 approval."
        }
      end)

    evidence_blockers ++
      [
        %{
          "code" => "implementation_refs_required",
          "message" => "Implementation PRs or local patches must be cited in the review packet."
        },
        %{
          "code" => "scrubbing_test_results_required",
          "message" => "Scrubbing pipeline rules and write/render boundary test results must be attached."
        },
        %{
          "code" => "owner_signoffs_required",
          "message" => "Owner sign-offs are required before a production decision."
        }
      ]
  end

  defp explicit_non_claims do
    [
      "phase4_review_plan_does_not_collect_live_provider_evidence",
      "phase4_review_plan_does_not_read_evidence_files",
      "phase4_review_plan_does_not_call_provider_apis",
      "phase4_review_plan_does_not_approve_production",
      "phase4_review_plan_does_not_enable_structured_execution_plan_gates"
    ]
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery Phase 4 review plan is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message) do
    %{
      code: code,
      path: path,
      message: message
    }
  end

  defp unique_strings(values) do
    values
    |> Enum.filter(&non_empty_string?/1)
    |> Enum.uniq()
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
