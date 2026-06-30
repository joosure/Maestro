defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceBundle do
  @moduledoc """
  Builds a bounded Phase 2 evidence bundle readiness projection.

  The bundle reconciles a Phase 2 evidence plan, the provider-owner evidence
  request, an optional provider preflight report, and completed evidence packet
  metadata. It does not read referenced evidence files, call providers, mutate
  workflow state, approve production, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    EvidencePacket,
    EvidenceRequest,
    Phase2EvidencePlan,
    PreflightReport
  }

  @schema "coding_pr_delivery.production_evidence_bundle.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @request_schema "coding_pr_delivery.production_evidence_request.v1"

  @type input :: Phase2EvidencePlan.plan() | String.t() | map()
  @type result :: {:ok, map()} | {:error, map()}

  @spec build(input(), keyword()) :: result()
  def build(input, opts \\ [])

  def build(input, opts) when is_list(opts) do
    with {:ok, phase2_plan} <- phase2_plan(input, opts),
         {:ok, request} <- EvidenceRequest.build(phase2_plan, plan_opts(opts)),
         {:ok, evidence_packets} <- evidence_packets(opts) do
      request_state = request_state(request, Keyword.get(opts, :evidence_request))
      preflight_state = preflight_state(phase2_plan, Keyword.get(opts, :preflight_report))
      evidence_state = evidence_state(phase2_plan, evidence_packets)
      provider_statuses = provider_statuses(phase2_plan, evidence_state)
      blockers = blockers(request_state, preflight_state, evidence_state, provider_statuses)

      {:ok, bundle(phase2_plan, request_state, preflight_state, evidence_state, provider_statuses, blockers)}
    end
  end

  def build(_input, _opts) do
    {:error, invalid([issue("invalid_options", [], "Evidence bundle options must be a keyword list.")])}
  end

  defp phase2_plan(%{"schema" => @phase2_schema} = plan, _opts), do: {:ok, plan}

  defp phase2_plan(plan, opts) do
    Phase2EvidencePlan.build(plan, plan_opts(opts))
  end

  defp plan_opts(opts) do
    opts
    |> Keyword.take([:plan_id, :tapd_cnb_shadow_run_id, :linear_cnb_shadow_run_id])
  end

  defp evidence_packets(opts) do
    cond do
      Keyword.has_key?(opts, :evidence_packets) ->
        case Keyword.fetch!(opts, :evidence_packets) do
          packets when is_list(packets) -> {:ok, packets}
          _packets -> {:error, invalid([issue("invalid_evidence_packets", [:evidence_packets], "Evidence packets must be a list.")])}
        end

      Keyword.has_key?(opts, :evidence_packet) ->
        {:ok, [Keyword.fetch!(opts, :evidence_packet)]}

      true ->
        {:ok, []}
    end
  end

  defp request_state(expected_request, nil) do
    %{
      provided?: false,
      valid?: true,
      status: "generated",
      request: expected_request,
      errors: []
    }
  end

  defp request_state(expected_request, provided_request) when is_map(provided_request) do
    errors =
      []
      |> maybe_add(
        Map.get(provided_request, "schema") != @request_schema,
        issue("invalid_evidence_request_schema", ["evidence_request", "schema"], "Evidence request schema is invalid.")
      )
      |> maybe_add(
        Map.get(provided_request, "phase2_plan_id") != Map.get(expected_request, "phase2_plan_id"),
        issue("evidence_request_plan_mismatch", ["evidence_request", "phase2_plan_id"], "Evidence request must match the Phase 2 plan id.")
      )
      |> maybe_add(
        Map.get(provided_request, "phase2_plan_kind") != Map.get(expected_request, "phase2_plan_kind"),
        issue("evidence_request_plan_mismatch", ["evidence_request", "phase2_plan_kind"], "Evidence request must match the Phase 2 plan kind.")
      )
      |> maybe_add(
        Map.get(provided_request, "provider_request_count") != Map.get(expected_request, "provider_request_count"),
        issue("evidence_request_provider_count_mismatch", ["evidence_request", "provider_request_count"], "Evidence request must match provider count.")
      )

    %{
      provided?: true,
      valid?: errors == [],
      status: if(errors == [], do: "provided", else: "invalid"),
      request: expected_request,
      errors: errors
    }
  end

  defp request_state(expected_request, _provided_request) do
    %{
      provided?: true,
      valid?: false,
      status: "invalid",
      request: expected_request,
      errors: [issue("invalid_evidence_request", ["evidence_request"], "Evidence request must be an object.")]
    }
  end

  defp preflight_state(_phase2_plan, nil) do
    %{provided?: false, valid?: false, status: "missing", errors: [], report: nil}
  end

  defp preflight_state(phase2_plan, report) do
    case PreflightReport.validate(report) do
      {:ok, normalized} ->
        mismatch_errors = phase2_mismatch_errors(phase2_plan, Map.get(normalized, "phase2_evidence_plan"), "preflight_report")

        %{
          provided?: true,
          valid?: mismatch_errors == [],
          status: if(mismatch_errors == [], do: Map.get(normalized, "status"), else: "invalid"),
          planned_count: Map.get(normalized, "planned_preflight_command_count", 0),
          result_count: Map.get(normalized, "preflight_result_count", 0),
          passed_count: count_results(normalized, "passed"),
          blocked_count: count_results(normalized, "blocked"),
          errors: mismatch_errors,
          report: normalized
        }

      {:error, reason} ->
        %{provided?: true, valid?: false, status: "invalid", errors: errors(reason), report: nil}
    end
  end

  defp evidence_state(phase2_plan, packets) do
    expected_sets = expected_entry_sets(phase2_plan)

    packet_states =
      packets
      |> Enum.with_index()
      |> Enum.map(fn {packet, index} -> evidence_packet_state(packet, index, expected_sets) end)

    %{
      provided_count: length(packets),
      packet_states: packet_states,
      valid_count: Enum.count(packet_states, & &1.valid?),
      invalid_count: Enum.count(packet_states, &(not &1.valid?)),
      expected_sets: expected_sets
    }
  end

  defp evidence_packet_state(packet, index, expected_sets) do
    case EvidencePacket.validate(packet) do
      {:ok, normalized} ->
        entry_ids = evidence_packet_entry_ids(normalized)
        matching_templates = matching_templates(entry_ids, expected_sets)

        %{
          index: index,
          valid?: true,
          status: "valid",
          provider_matrix_entry_ids: entry_ids,
          matching_templates: matching_templates,
          scenario_evidence_count: length(Map.get(normalized, "scenario_evidence", [])),
          errors: []
        }

      {:error, reason} ->
        %{
          index: index,
          valid?: false,
          status: "invalid",
          provider_matrix_entry_ids: [],
          matching_templates: [],
          scenario_evidence_count: 0,
          errors: errors(reason)
        }
    end
  end

  defp provider_statuses(phase2_plan, evidence_state) do
    packet_states = Map.fetch!(evidence_state, :packet_states)

    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.map(fn provider_plan ->
      template = Map.get(provider_plan, "template")
      entry_ids = Map.get(provider_plan, "provider_matrix_entry_ids", [])
      matching_packets = Enum.filter(packet_states, &(template in &1.matching_templates))

      %{
        "template" => template,
        "tier" => Map.get(provider_plan, "tier"),
        "provider_matrix_entry_ids" => entry_ids,
        "tracker_kinds" => Map.get(provider_plan, "tracker_kinds", []),
        "repo_provider_kinds" => Map.get(provider_plan, "repo_provider_kinds", []),
        "side_effect_modes" => Map.get(provider_plan, "side_effect_modes", []),
        "evidence_packet_status" => evidence_status(matching_packets),
        "matching_evidence_packet_count" => length(matching_packets),
        "review_packet_template_ready" => length(matching_packets) == 1
      }
    end)
  end

  defp evidence_status([]), do: "missing"
  defp evidence_status([_packet]), do: "valid"
  defp evidence_status(_packets), do: "duplicate"

  defp blockers(request_state, preflight_state, evidence_state, provider_statuses) do
    []
    |> request_blockers(request_state)
    |> preflight_blockers(preflight_state)
    |> evidence_packet_blockers(evidence_state)
    |> provider_status_blockers(provider_statuses)
  end

  defp request_blockers(blockers, %{valid?: true}), do: blockers

  defp request_blockers(blockers, %{errors: errors}) do
    [
      %{
        "code" => "evidence_request_invalid",
        "message" => "Provided evidence request must match the Phase 2 evidence plan.",
        "error_count" => length(errors),
        "errors" => Enum.map(errors, &error_to_map/1)
      }
      | blockers
    ]
  end

  defp preflight_blockers(blockers, %{provided?: false}) do
    [
      %{
        "code" => "provider_preflight_report_required",
        "message" => "Provider preflight report is required before Phase 2 evidence can enter review."
      }
      | blockers
    ]
  end

  defp preflight_blockers(blockers, %{valid?: false, errors: errors}) do
    [
      %{
        "code" => "provider_preflight_report_invalid",
        "message" => "Provider preflight report must validate against the Phase 2 plan.",
        "error_count" => length(errors),
        "errors" => Enum.map(errors, &error_to_map/1)
      }
      | blockers
    ]
  end

  defp preflight_blockers(blockers, %{status: "passed"}), do: blockers

  defp preflight_blockers(blockers, %{status: "blocked", report: report}) do
    [
      %{
        "code" => "provider_preflight_blocked",
        "message" => "Provider preflight must pass before completed evidence can enter review.",
        "blocked_count" => count_results(report, "blocked")
      }
      | blockers
    ]
  end

  defp preflight_blockers(blockers, _preflight), do: blockers

  defp evidence_packet_blockers(blockers, %{provided_count: 0}) do
    [
      %{
        "code" => "completed_evidence_packet_required",
        "message" => "At least one completed evidence packet is required before Phase 4 review."
      }
      | blockers
    ]
  end

  defp evidence_packet_blockers(blockers, %{packet_states: packet_states}) do
    invalid =
      packet_states
      |> Enum.filter(&(not &1.valid?))
      |> Enum.map(fn packet_state ->
        %{
          "code" => "completed_evidence_packet_invalid",
          "message" => "Completed evidence packet metadata must validate.",
          "packet_index" => packet_state.index,
          "error_count" => length(packet_state.errors),
          "errors" => Enum.map(packet_state.errors, &error_to_map/1)
        }
      end)

    unknown =
      packet_states
      |> Enum.filter(&(&1.valid? and &1.matching_templates == []))
      |> Enum.map(fn packet_state ->
        %{
          "code" => "completed_evidence_packet_unmatched",
          "message" => "Completed evidence packet provider entries must match a Phase 2 provider plan.",
          "packet_index" => packet_state.index,
          "provider_matrix_entry_ids" => packet_state.provider_matrix_entry_ids
        }
      end)

    invalid ++ unknown ++ blockers
  end

  defp provider_status_blockers(blockers, provider_statuses) do
    provider_statuses
    |> Enum.reject(&(&1["evidence_packet_status"] == "valid"))
    |> Enum.map(fn status ->
      %{
        "code" => "provider_evidence_packet_#{status["evidence_packet_status"]}",
        "message" => "Each Phase 2 provider plan must have exactly one matching completed evidence packet.",
        "template" => status["template"],
        "provider_matrix_entry_ids" => status["provider_matrix_entry_ids"]
      }
    end)
    |> Kernel.++(blockers)
  end

  defp bundle(phase2_plan, request_state, preflight_state, evidence_state, provider_statuses, blockers) do
    %{
      "schema" => @schema,
      "status" => if(blockers == [], do: "ready_for_phase4_review", else: "blocked"),
      "phase4_ready" => blockers == [],
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "provider_plan_count" => length(Map.get(phase2_plan, "provider_plans", [])),
      "evidence_request" => request_summary(request_state),
      "preflight" => preflight_summary(preflight_state),
      "evidence_packets" => evidence_summary(evidence_state),
      "provider_bundle_statuses" => provider_statuses,
      "blockers" => blockers,
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

  defp request_summary(%{request: request} = state) do
    %{
      "provided" => Map.get(state, :provided?),
      "valid" => Map.get(state, :valid?),
      "status" => Map.get(state, :status),
      "provider_request_count" => Map.get(request, "provider_request_count", 0),
      "error_count" => length(Map.get(state, :errors, []))
    }
  end

  defp preflight_summary(%{provided?: false}) do
    %{
      "provided" => false,
      "valid" => false,
      "status" => "missing",
      "planned_preflight_command_count" => 0,
      "preflight_result_count" => 0,
      "passed_count" => 0,
      "blocked_count" => 0,
      "error_count" => 0
    }
  end

  defp preflight_summary(preflight) do
    %{
      "provided" => Map.get(preflight, :provided?),
      "valid" => Map.get(preflight, :valid?),
      "status" => Map.get(preflight, :status),
      "planned_preflight_command_count" => Map.get(preflight, :planned_count, 0),
      "preflight_result_count" => Map.get(preflight, :result_count, 0),
      "passed_count" => Map.get(preflight, :passed_count, 0),
      "blocked_count" => Map.get(preflight, :blocked_count, 0),
      "error_count" => length(Map.get(preflight, :errors, []))
    }
  end

  defp evidence_summary(evidence_state) do
    %{
      "provided_count" => Map.get(evidence_state, :provided_count),
      "valid_count" => Map.get(evidence_state, :valid_count),
      "invalid_count" => Map.get(evidence_state, :invalid_count),
      "expected_provider_plan_count" => length(Map.get(evidence_state, :expected_sets, [])),
      "packets" => Enum.map(Map.get(evidence_state, :packet_states, []), &packet_summary/1)
    }
  end

  defp packet_summary(packet_state) do
    %{
      "packet_index" => packet_state.index,
      "status" => packet_state.status,
      "provider_matrix_entry_ids" => packet_state.provider_matrix_entry_ids,
      "matching_templates" => packet_state.matching_templates,
      "scenario_evidence_count" => packet_state.scenario_evidence_count,
      "error_count" => length(packet_state.errors)
    }
  end

  defp expected_entry_sets(phase2_plan) do
    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.map(fn provider_plan ->
      %{
        template: Map.get(provider_plan, "template"),
        entry_ids: provider_plan |> Map.get("provider_matrix_entry_ids", []) |> Enum.sort()
      }
    end)
  end

  defp matching_templates(entry_ids, expected_sets) do
    sorted_ids = Enum.sort(entry_ids)

    expected_sets
    |> Enum.filter(&(&1.entry_ids == sorted_ids))
    |> Enum.map(& &1.template)
  end

  defp evidence_packet_entry_ids(packet) do
    packet
    |> value_at(["production_claim", "provider_matrix"])
    |> case do
      entries when is_list(entries) ->
        entries
        |> Enum.map(&Map.get(&1, "id"))
        |> Enum.filter(&non_empty_string?/1)
        |> Enum.sort()

      _entries ->
        []
    end
  end

  defp phase2_mismatch_errors(phase2_plan, compared_plan, label) do
    []
    |> maybe_add(
      Map.get(compared_plan || %{}, "schema") != @phase2_schema,
      issue("#{label}_phase2_schema_mismatch", [label, "phase2_evidence_plan", "schema"], "Nested Phase 2 evidence plan schema is invalid.")
    )
    |> maybe_add(
      Map.get(compared_plan || %{}, "plan_id") != Map.get(phase2_plan, "plan_id"),
      issue("#{label}_phase2_plan_mismatch", [label, "phase2_evidence_plan", "plan_id"], "Nested Phase 2 evidence plan id must match.")
    )
    |> maybe_add(
      Map.get(compared_plan || %{}, "plan_kind") != Map.get(phase2_plan, "plan_kind"),
      issue("#{label}_phase2_plan_mismatch", [label, "phase2_evidence_plan", "plan_kind"], "Nested Phase 2 evidence plan kind must match.")
    )
  end

  defp count_results(nil, _status), do: 0

  defp count_results(report, status) do
    report
    |> Map.get("provider_preflight_results", [])
    |> Enum.count(&(Map.get(&1, "status") == status))
  end

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "production_evidence_bundle_error", "message" => "Evidence bundle projection failed."}

  defp invalid(errors) do
    %{
      code: "coding_pr_delivery_evidence_bundle_invalid",
      message: "Coding PR Delivery production evidence bundle is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, meta \\ %{}) do
    %{code: code, path: path, message: message, meta: meta}
  end

  defp maybe_add(errors, true, issue), do: errors ++ [issue]
  defp maybe_add(errors, false, _issue), do: errors

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

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""
end
