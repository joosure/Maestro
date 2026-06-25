defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.StatusReport do
  @moduledoc """
  Builds a bounded Coding PR Delivery production-profile status projection.

  The report reconciles a Phase 2 evidence plan, the static Phase 4 review plan,
  and an optional provider preflight report. It summarizes why production review
  is still blocked without reading evidence files, calling providers, mutating
  workflow state, approving production, or enabling gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Phase2EvidencePlan,
    Phase4ReviewPlan,
    PreflightReport
  }

  @schema "coding_pr_delivery.production_profile_status.v1"
  @phase2_schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @preflight_required_code "provider_preflight_report_required"

  @type input :: Phase2EvidencePlan.plan() | String.t() | map()
  @type result :: {:ok, map()} | {:error, map()}

  @spec build(input(), keyword()) :: result()
  def build(input, opts \\ [])

  def build(input, opts) when is_list(opts) do
    with {:ok, phase2_plan} <- phase2_plan(input, opts),
         {:ok, phase4_plan} <- Phase4ReviewPlan.build(phase2_plan, plan_opts(opts)) do
      preflight = preflight_state(Keyword.get(opts, :preflight_report))
      blockers = reconcile_blockers(Map.get(phase4_plan, "blocking_requirements", []), preflight)

      {:ok, status_report(phase2_plan, phase4_plan, preflight, blockers)}
    end
  end

  def build(_input, _opts) do
    {:error, invalid([issue("invalid_options", [], "Status report options must be a keyword list.")])}
  end

  defp phase2_plan(%{"schema" => @phase2_schema} = plan, _opts), do: {:ok, plan}
  defp phase2_plan(plan, opts), do: Phase2EvidencePlan.build(plan, plan_opts(opts))

  defp plan_opts(opts) do
    opts
    |> Keyword.take([:plan_id, :tapd_cnb_shadow_run_id, :linear_cnb_shadow_run_id])
  end

  defp status_report(phase2_plan, phase4_plan, preflight, blockers) do
    %{
      "schema" => @schema,
      "status" => if(blockers == [], do: "ready_for_phase4_review", else: "blocked"),
      "phase4_ready" => blockers == [],
      "phase2_plan_id" => Map.get(phase2_plan, "plan_id"),
      "phase2_plan_kind" => Map.get(phase2_plan, "plan_kind"),
      "phase4_plan_id" => Map.get(phase4_plan, "plan_id"),
      "provider_plan_count" => length(Map.get(phase2_plan, "provider_plans", [])),
      "provider_entries" => provider_entries(phase2_plan),
      "preflight" => preflight_summary(preflight),
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

  defp provider_entries(phase2_plan) do
    phase2_plan
    |> Map.get("provider_plans", [])
    |> Enum.map(fn provider_plan ->
      %{
        "template" => Map.get(provider_plan, "template"),
        "tier" => Map.get(provider_plan, "tier"),
        "provider_matrix_entry_ids" => Map.get(provider_plan, "provider_matrix_entry_ids", []),
        "tracker_kinds" => Map.get(provider_plan, "tracker_kinds", []),
        "repo_provider_kinds" => Map.get(provider_plan, "repo_provider_kinds", []),
        "side_effect_modes" => Map.get(provider_plan, "side_effect_modes", []),
        "live_evidence_status" => Map.get(provider_plan, "live_evidence_status")
      }
    end)
  end

  defp preflight_state(nil), do: %{provided?: false, valid?: false, status: "missing", results: [], errors: []}

  defp preflight_state(report) do
    case PreflightReport.validate(report) do
      {:ok, normalized} ->
        %{
          provided?: true,
          valid?: true,
          status: Map.get(normalized, "status"),
          planned_count: Map.get(normalized, "planned_preflight_command_count", 0),
          result_count: Map.get(normalized, "preflight_result_count", 0),
          results: Map.get(normalized, "provider_preflight_results", []),
          errors: []
        }

      {:error, reason} ->
        %{provided?: true, valid?: false, status: "invalid", results: [], errors: errors(reason)}
    end
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
      "blocked_results" => [],
      "errors" => []
    }
  end

  defp preflight_summary(%{valid?: false, errors: errors}) do
    %{
      "provided" => true,
      "valid" => false,
      "status" => "invalid",
      "planned_preflight_command_count" => 0,
      "preflight_result_count" => 0,
      "passed_count" => 0,
      "blocked_count" => 0,
      "blocked_results" => [],
      "errors" => errors
    }
  end

  defp preflight_summary(%{results: results} = preflight) do
    blocked_results = Enum.filter(results, &(Map.get(&1, "status") == "blocked"))

    %{
      "provided" => true,
      "valid" => true,
      "status" => Map.get(preflight, :status),
      "planned_preflight_command_count" => Map.get(preflight, :planned_count, 0),
      "preflight_result_count" => Map.get(preflight, :result_count, 0),
      "passed_count" => Enum.count(results, &(Map.get(&1, "status") == "passed")),
      "blocked_count" => length(blocked_results),
      "blocked_results" => Enum.map(blocked_results, &blocked_preflight_summary/1),
      "errors" => []
    }
  end

  defp blocked_preflight_summary(result) do
    %{
      "template" => Map.get(result, "template"),
      "command_id" => Map.get(result, "command_id"),
      "target" => Map.get(result, "target"),
      "provider_kind" => Map.get(result, "provider_kind"),
      "blocker_code" => Map.get(result, "blocker_code"),
      "missing_prerequisites" => Map.get(result, "missing_prerequisites", [])
    }
  end

  defp reconcile_blockers(blockers, %{provided?: false}), do: blockers

  defp reconcile_blockers(blockers, %{valid?: false, errors: errors}) do
    blockers
    |> without_preflight_required()
    |> then(&[preflight_invalid_blocker(errors) | &1])
  end

  defp reconcile_blockers(blockers, %{status: "passed"}), do: without_preflight_required(blockers)

  defp reconcile_blockers(blockers, %{status: "blocked", results: results}) do
    preflight_blockers =
      results
      |> Enum.filter(&(Map.get(&1, "status") == "blocked"))
      |> Enum.map(&preflight_blocked_blocker/1)

    preflight_blockers ++ without_preflight_required(blockers)
  end

  defp reconcile_blockers(blockers, _preflight), do: blockers

  defp without_preflight_required(blockers) do
    Enum.reject(blockers, &(Map.get(&1, "code") == @preflight_required_code))
  end

  defp preflight_invalid_blocker(errors) do
    %{
      "code" => "provider_preflight_report_invalid",
      "message" => "Provider preflight report must validate before completed evidence collection.",
      "error_count" => length(errors),
      "errors" => errors
    }
  end

  defp preflight_blocked_blocker(result) do
    %{
      "code" => "provider_preflight_blocked",
      "message" => "Provider preflight remains blocked by missing prerequisites.",
      "template" => Map.get(result, "template"),
      "command_id" => Map.get(result, "command_id"),
      "provider_kind" => Map.get(result, "provider_kind"),
      "target" => Map.get(result, "target"),
      "blocker_code" => Map.get(result, "blocker_code"),
      "missing_prerequisites" => Map.get(result, "missing_prerequisites", [])
    }
  end

  defp errors(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &error_to_map/1)

  defp error_to_map(error) when is_map(error) do
    error
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp error_to_map(_error), do: %{"code" => "status_report_error", "message" => "Status report failed."}

  defp invalid(errors) do
    %{
      code: "coding_pr_delivery_status_report_invalid",
      message: "Coding PR Delivery production-profile status report is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, meta \\ %{}) do
    %{code: code, path: path, message: message, meta: meta}
  end
end
