defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceHandoff do
  @moduledoc """
  Builds a bounded Phase 2 provider-evidence handoff package.

  The package gives provider owners one metadata view over the Phase 2 evidence
  plan, provider-owner request, production status, and evidence bundle readiness.
  It does not read referenced evidence files, call providers, mutate workflow
  state, approve production, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    EvidenceBundle,
    EvidenceRequest,
    Phase2EvidencePlan,
    StatusReport
  }

  @schema "coding_pr_delivery.production_evidence_handoff.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"

  @type input :: Phase2EvidencePlan.plan() | String.t() | map()
  @type result :: {:ok, map()} | {:error, map()}

  @spec build(input(), keyword()) :: result()
  def build(input, opts \\ [])

  def build(input, opts) when is_list(opts) do
    with {:ok, phase2_plan} <- phase2_plan(input, opts),
         {:ok, request} <- EvidenceRequest.build(phase2_plan, plan_opts(opts)),
         {:ok, status} <- StatusReport.build(phase2_plan, status_opts(opts)),
         {:ok, bundle} <- EvidenceBundle.build(phase2_plan, bundle_opts(opts)) do
      {:ok, handoff(phase2_plan, request, status, bundle)}
    end
  end

  def build(_input, _opts) do
    {:error, invalid([issue("invalid_options", [], "Evidence handoff options must be a keyword list.")])}
  end

  defp phase2_plan(%{"schema" => @phase2_schema} = plan, _opts), do: {:ok, plan}
  defp phase2_plan(plan, opts), do: Phase2EvidencePlan.build(plan, plan_opts(opts))

  defp plan_opts(opts) do
    Keyword.take(opts, [:plan_id, :tapd_cnb_shadow_run_id, :linear_cnb_shadow_run_id])
  end

  defp status_opts(opts) do
    opts
    |> plan_opts()
    |> maybe_put(:preflight_report, Keyword.get(opts, :preflight_report))
  end

  defp bundle_opts(opts) do
    opts
    |> Keyword.take([
      :plan_id,
      :tapd_cnb_shadow_run_id,
      :linear_cnb_shadow_run_id,
      :evidence_request,
      :preflight_report,
      :evidence_packet,
      :evidence_packets
    ])
  end

  defp handoff(phase2_plan, request, status, bundle) do
    %{
      "schema" => @schema,
      "status" => handoff_status(bundle),
      "phase4_ready" => Map.get(bundle, "phase4_ready", false),
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "provider_plan_count" => length(Map.get(phase2_plan, "provider_plans", [])),
      "provider_handoffs" => provider_handoffs(request, bundle),
      "external_input_summary" => Map.get(request, "external_input_summary", %{}),
      "preflight" => Map.get(status, "preflight", %{}),
      "status_blocker_count" => length(Map.get(status, "blockers", [])),
      "evidence_bundle" => bundle_summary(bundle),
      "operator_commands" => operator_commands(Map.get(phase2_plan, "plan_kind")),
      "blockers" => Map.get(bundle, "blockers", []),
      "required_next_step" => required_next_step(bundle),
      "does_not_collect_live_evidence" => true,
      "does_not_read_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true,
      "raw_input_included" => false,
      "normalized_artifacts_included" => false
    }
  end

  defp handoff_status(%{"phase4_ready" => true}), do: "ready_for_phase4_review"
  defp handoff_status(_bundle), do: "blocked_pending_external_evidence"

  defp required_next_step(%{"phase4_ready" => true}) do
    "build and validate the Phase 4 review packet with owner sign-off"
  end

  defp required_next_step(_bundle) do
    "supply provider credentials and concrete targets, run read-only preflight, collect provider evidence, then rebuild this handoff package"
  end

  defp provider_handoffs(request, bundle) do
    bundle_statuses = Map.get(bundle, "provider_bundle_statuses", [])

    request
    |> Map.get("provider_requests", [])
    |> Enum.map(fn provider_request ->
      bundle_status = matching_bundle_status(bundle_statuses, provider_request)

      %{
        "template" => Map.get(provider_request, "template"),
        "tier" => Map.get(provider_request, "tier"),
        "provider_matrix_entry_ids" => Map.get(provider_request, "provider_matrix_entry_ids", []),
        "tracker_kinds" => Map.get(provider_request, "tracker_kinds", []),
        "repo_provider_kinds" => Map.get(provider_request, "repo_provider_kinds", []),
        "side_effect_modes" => Map.get(provider_request, "side_effect_modes", []),
        "live_evidence_status" => Map.get(provider_request, "live_evidence_status"),
        "required_access" => Map.get(provider_request, "required_access", %{}),
        "preflight_command_count" => length(Map.get(provider_request, "read_only_preflight_commands", [])),
        "evidence_requirement_count" => length(Map.get(provider_request, "evidence_requirements", [])),
        "evidence_destinations" => evidence_destinations(provider_request),
        "owner_actions" => Map.get(provider_request, "owner_actions", []),
        "evidence_packet_status" => Map.get(bundle_status, "evidence_packet_status", "missing"),
        "matching_evidence_packet_count" => Map.get(bundle_status, "matching_evidence_packet_count", 0),
        "review_packet_template_ready" => Map.get(bundle_status, "review_packet_template_ready", false)
      }
    end)
  end

  defp matching_bundle_status(statuses, provider_request) do
    template = Map.get(provider_request, "template")

    Enum.find(statuses, %{}, &(Map.get(&1, "template") == template))
  end

  defp evidence_destinations(provider_request) do
    provider_request
    |> Map.get("evidence_requirements", [])
    |> Enum.flat_map(&Map.get(&1, "evidence_files", []))
    |> Enum.filter(&non_empty_string?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp bundle_summary(bundle) do
    %{
      "status" => Map.get(bundle, "status"),
      "phase4_ready" => Map.get(bundle, "phase4_ready"),
      "evidence_request" => Map.get(bundle, "evidence_request", %{}),
      "preflight" => Map.get(bundle, "preflight", %{}),
      "evidence_packets" => Map.get(bundle, "evidence_packets", %{}),
      "blocker_count" => length(Map.get(bundle, "blockers", []))
    }
  end

  defp operator_commands(plan_kind) do
    [
      %{
        "name" => "collect_read_only_preflight",
        "command_id" => "symphony.workflow.extension.coding_pr_delivery.production_profile_preflight_collect",
        "args" => ["--plan", plan_kind, "--repo", "<provider/repo>", "--pr", "<pr-number>", "--json"],
        "requires_external_access" => true,
        "does_not_authorize_writes" => true
      },
      %{
        "name" => "export_provider_evidence_request",
        "command_id" => "symphony.workflow.extension.coding_pr_delivery.production_profile_evidence_request",
        "args" => ["--plan", plan_kind, "--json"],
        "requires_external_access" => false,
        "does_not_authorize_writes" => true
      },
      %{
        "name" => "validate_completed_evidence_packet",
        "command_id" => "symphony.workflow.extension.coding_pr_delivery.production_profile_validate",
        "args" => ["--kind", "evidence_packet", "--file", "<completed-evidence-packet.json>", "--json"],
        "requires_external_access" => false,
        "does_not_authorize_writes" => true
      },
      %{
        "name" => "rebuild_evidence_handoff",
        "command_id" => "symphony.workflow.extension.coding_pr_delivery.production_profile_evidence_handoff",
        "args" => [
          "--phase2-plan-file",
          "<phase2-plan.json>",
          "--evidence-request-file",
          "<evidence-request.json>",
          "--preflight-report-file",
          "<preflight-report.json>",
          "--evidence-packet-file",
          "<completed-evidence-packet.json>",
          "--json"
        ],
        "requires_external_access" => false,
        "does_not_authorize_writes" => true
      }
    ]
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp invalid(errors) do
    %{
      code: "coding_pr_delivery_evidence_handoff_invalid",
      message: "Coding PR Delivery production evidence handoff is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, meta \\ %{}) do
    %{code: code, path: path, message: message, meta: meta}
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
