defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRequest do
  @moduledoc """
  Builds bounded provider-evidence request packets from Phase 2 evidence plans.

  The request is an operator/provider-owner handoff artifact. It names the
  credentials, auth checks, concrete targets, read-only preflight probes, and
  evidence files needed before Phase 4 can be reviewed. It does not read
  evidence files, call providers, mutate workflow state, approve production, or
  enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan

  @schema "coding_pr_delivery.production_evidence_request.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"

  @type input :: Phase2EvidencePlan.plan() | String.t() | map()
  @type result :: {:ok, map()} | {:error, map()}

  @spec build(input(), keyword()) :: result()
  def build(input, opts \\ [])

  def build(input, opts) when is_list(opts) do
    with {:ok, phase2_plan} <- phase2_plan(input, opts) do
      {:ok, evidence_request(phase2_plan)}
    end
  end

  def build(_input, _opts) do
    {:error, invalid([issue("invalid_options", [], "Evidence request options must be a keyword list.")])}
  end

  defp phase2_plan(%{"schema" => @phase2_schema} = plan, _opts), do: {:ok, plan}

  defp phase2_plan(plan, opts) do
    opts =
      opts
      |> Keyword.take([:plan_id, :tapd_cnb_shadow_run_id, :linear_cnb_shadow_run_id])

    Phase2EvidencePlan.build(plan, opts)
  end

  defp evidence_request(phase2_plan) do
    provider_requests = provider_requests(phase2_plan)

    %{
      "schema" => @schema,
      "status" => "blocked_pending_external_evidence",
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "request_authority" => "phase2_provider_evidence_request_only",
      "provider_request_count" => length(provider_requests),
      "provider_requests" => provider_requests,
      "external_input_summary" => external_input_summary(provider_requests),
      "required_next_step" => "supply provider credentials and concrete targets, run read-only preflight, then collect and validate provider evidence",
      "does_not_collect_live_evidence" => true,
      "does_not_read_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_approve_production" => true,
      "does_not_enable_production" => true,
      "raw_input_included" => false,
      "normalized_plan_included" => false
    }
  end

  defp provider_requests(phase2_plan) do
    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.map(&provider_request/1)
  end

  defp provider_request(provider_plan) do
    preflight_commands = preflight_commands(provider_plan)
    evidence_requirements = evidence_requirements(provider_plan)

    %{
      "template" => Map.get(provider_plan, "template"),
      "tier" => Map.get(provider_plan, "tier"),
      "provider_matrix_entry_ids" => Map.get(provider_plan, "provider_matrix_entry_ids", []),
      "tracker_kinds" => Map.get(provider_plan, "tracker_kinds", []),
      "repo_provider_kinds" => Map.get(provider_plan, "repo_provider_kinds", []),
      "side_effect_modes" => Map.get(provider_plan, "side_effect_modes", []),
      "live_evidence_status" => Map.get(provider_plan, "live_evidence_status"),
      "required_access" => required_access(preflight_commands),
      "read_only_preflight_commands" => preflight_commands,
      "evidence_requirements" => evidence_requirements,
      "non_claim_acknowledgements" => non_claim_acknowledgements(provider_plan),
      "owner_actions" => owner_actions(provider_plan),
      "does_not_authorize_production_writes" => true
    }
  end

  defp preflight_commands(provider_plan) do
    provider_plan
    |> value_at(["read_only_preflight", "commands"])
    |> case do
      commands when is_list(commands) ->
        Enum.map(commands, &preflight_command/1)

      _missing ->
        []
    end
  end

  defp preflight_command(command) do
    %{
      "id" => Map.get(command, "id"),
      "target" => Map.get(command, "target"),
      "provider_kind" => Map.get(command, "provider_kind"),
      "command" => Map.get(command, "command"),
      "side_effect_mode" => Map.get(command, "side_effect_mode"),
      "does_not_write" => Map.get(command, "does_not_write"),
      "required_env" => Map.get(command, "required_env", []),
      "required_auth" => Map.get(command, "required_auth", []),
      "required_targets" => Map.get(command, "required_targets", []),
      "required_runtime" => Map.get(command, "required_runtime", [])
    }
  end

  defp required_access(preflight_commands) do
    %{
      "required_env" => unique_flat(preflight_commands, "required_env"),
      "required_auth" => unique_flat(preflight_commands, "required_auth"),
      "required_targets" => unique_flat(preflight_commands, "required_targets"),
      "required_runtime" => unique_flat(preflight_commands, "required_runtime")
    }
  end

  defp evidence_requirements(provider_plan) do
    provider_plan
    |> value_at(["evidence_packet_template", "scenario_evidence_requirements"])
    |> case do
      requirements when is_list(requirements) ->
        Enum.map(requirements, &evidence_requirement/1)

      _missing ->
        []
    end
  end

  defp evidence_requirement(requirement) do
    %{
      "scenario_id" => Map.get(requirement, "scenario_id"),
      "scenario_title" => Map.get(requirement, "scenario_title"),
      "provider_matrix_entry_id" => Map.get(requirement, "provider_matrix_entry_id"),
      "required_evidence_kind" => Map.get(requirement, "required_evidence_kind"),
      "required_status" => Map.get(requirement, "required_status"),
      "evidence_files" => Map.get(requirement, "evidence_files", []),
      "allowed_evidence_ref_prefixes" => Map.get(requirement, "allowed_evidence_ref_prefixes", []),
      "raw_provider_output_allowed" => Map.get(requirement, "raw_provider_output_allowed"),
      "no_write_flags" => Map.get(requirement, "no_write_flags"),
      "shadow" => shadow_summary(Map.get(requirement, "shadow"))
    }
  end

  defp shadow_summary(shadow) when is_map(shadow) do
    %{
      "prefix" => Map.get(shadow, "prefix"),
      "run_id" => Map.get(shadow, "run_id"),
      "authority" => Map.get(shadow, "authority"),
      "canonical_authority" => Map.get(shadow, "canonical_authority"),
      "allowed_destinations" => Map.get(shadow, "allowed_destinations", [])
    }
  end

  defp shadow_summary(_shadow), do: nil

  defp non_claim_acknowledgements(provider_plan) do
    provider_plan
    |> value_at(["evidence_packet_template", "non_claim_acknowledgement_requirements"])
    |> case do
      requirements when is_list(requirements) ->
        Enum.map(requirements, fn requirement ->
          %{
            "provider_matrix_entry_id" => Map.get(requirement, "provider_matrix_entry_id"),
            "non_claims" => Map.get(requirement, "non_claims", []),
            "fields_to_complete" => Map.get(requirement, "fields_to_complete", [])
          }
        end)

      _missing ->
        []
    end
  end

  defp owner_actions(provider_plan) do
    [
      "provide_required_access",
      "provide_concrete_targets",
      "run_read_only_preflight",
      evidence_action(provider_plan),
      "validate_completed_evidence_packet"
    ]
  end

  defp evidence_action(provider_plan) do
    if "shadow_no_write" in Map.get(provider_plan, "side_effect_modes", []) do
      "collect_shadow_no_write_evidence"
    else
      "collect_ready_to_land_evidence"
    end
  end

  defp external_input_summary(provider_requests) do
    required_access =
      provider_requests
      |> Enum.map(&Map.get(&1, "required_access", %{}))

    %{
      "required_env" => unique_flat(required_access, "required_env"),
      "required_auth" => unique_flat(required_access, "required_auth"),
      "required_targets" => unique_flat(required_access, "required_targets"),
      "required_runtime" => unique_flat(required_access, "required_runtime")
    }
  end

  defp unique_flat(values, field) do
    values
    |> Enum.flat_map(fn value ->
      case Map.get(value, field) do
        items when is_list(items) -> items
        _missing -> []
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp value_at(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn key, current ->
      if is_map(current) and Map.has_key?(current, key) do
        {:cont, Map.get(current, key)}
      else
        {:halt, nil}
      end
    end)
  end

  defp value_at(_map, _path), do: nil

  defp invalid(errors) do
    %{
      code: "coding_pr_delivery_evidence_request_invalid",
      message: "Coding PR Delivery production evidence request is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, meta \\ %{}) do
    %{code: code, path: path, message: message, meta: meta}
  end
end
