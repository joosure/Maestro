defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Phase2EvidencePlan do
  @moduledoc """
  Builds bounded Phase 2 evidence plans for provider-matrix candidates.

  The plan is a deterministic aggregation over production-claim templates,
  evidence runbooks, and evidence-packet templates. It does not collect live
  evidence, read evidence files, call providers, mutate workflow state, or
  enable production gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    EvidencePacketTemplate,
    EvidenceRunbook,
    Phase2ClaimTemplate
  }

  @schema "coding_pr_delivery.phase2_evidence_plan.v1"
  @error_code "coding_pr_delivery_phase2_evidence_plan_invalid"
  @plan_ids ["tiered_reference", "linear_github_ready", "tapd_cnb_shadow", "linear_cnb_shadow"]
  @single_template_plans ["linear_github_ready", "tapd_cnb_shadow", "linear_cnb_shadow"]
  @tier_by_template %{
    "linear_github_ready" => "tier_1_reference",
    "tapd_cnb_shadow" => "tier_2_cnb_shadow",
    "linear_cnb_shadow" => "tier_2_cnb_shadow"
  }

  @type plan :: :tiered_reference | :linear_github_ready | :tapd_cnb_shadow | :linear_cnb_shadow
  @type result :: {:ok, map()} | {:error, map()}

  @spec plans() :: [String.t()]
  def plans, do: @plan_ids

  @spec build(plan() | String.t(), keyword()) :: result()
  def build(plan, opts \\ [])

  def build(plan, opts) when is_list(opts) do
    with {:ok, plan_id} <- normalize_plan(plan),
         {:ok, entries} <- build_entries(plan_id, opts) do
      {:ok, evidence_plan(plan_id, entries, opts)}
    end
  end

  def build(_plan, _opts) do
    {:error, invalid([issue("invalid_options", [], "Phase 2 evidence plan options must be a keyword list.")])}
  end

  defp normalize_plan(plan) when is_atom(plan), do: normalize_plan(Atom.to_string(plan))

  defp normalize_plan(plan) when is_binary(plan) do
    plan_id = String.trim(plan)

    if plan_id in @plan_ids do
      {:ok, plan_id}
    else
      {:error, invalid([issue("unknown_plan", ["plan"], "Phase 2 evidence plan is not supported.", %{allowed_values: @plan_ids})])}
    end
  end

  defp normalize_plan(_plan) do
    {:error, invalid([issue("invalid_plan", ["plan"], "Phase 2 evidence plan must be a string or atom.", %{allowed_values: @plan_ids})])}
  end

  defp build_entries("tiered_reference", opts) do
    [
      {"tier_1_reference", "linear_github_ready"},
      {"tier_2_cnb_shadow", "tapd_cnb_shadow"},
      {"tier_2_cnb_shadow", "linear_cnb_shadow"}
    ]
    |> build_template_entries(opts)
  end

  defp build_entries(plan_id, opts) when plan_id in @single_template_plans do
    build_template_entries([{Map.fetch!(@tier_by_template, plan_id), plan_id}], opts)
  end

  defp build_template_entries(entries, opts) do
    entries
    |> Enum.reduce_while({:ok, []}, fn {tier, template_id}, {:ok, acc} ->
      case build_template_entry(tier, template_id, opts) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_template_entry(tier, template_id, opts) do
    with {:ok, claim} <- Phase2ClaimTemplate.build(template_id, template_opts(template_id, opts)),
         {:ok, runbook} <- EvidenceRunbook.build(claim),
         {:ok, evidence_template} <- EvidencePacketTemplate.build(claim) do
      {:ok, plan_entry(tier, template_id, claim, runbook, evidence_template)}
    else
      {:error, reason} ->
        {:error,
         invalid([
           issue("template_build_failed", ["provider_plans", template_id], "Provider evidence-plan template failed validation.", %{
             template: template_id,
             reason: reason
           })
         ])}
    end
  end

  defp template_opts("tapd_cnb_shadow", opts) do
    put_shadow_run_id(opts, Keyword.get(opts, :tapd_cnb_shadow_run_id, "tapd-cnb-shadow-run-1"))
  end

  defp template_opts("linear_cnb_shadow", opts) do
    put_shadow_run_id(opts, Keyword.get(opts, :linear_cnb_shadow_run_id, "linear-cnb-shadow-run-1"))
  end

  defp template_opts(_template_id, opts), do: opts

  defp put_shadow_run_id(opts, shadow_run_id) do
    opts
    |> Keyword.delete(:shadow_run_id)
    |> Keyword.put(:shadow_run_id, shadow_run_id)
  end

  defp evidence_plan(plan_id, entries, opts) do
    %{
      "schema" => @schema,
      "plan_id" => Keyword.get(opts, :plan_id, "coding_pr_delivery.phase2.#{plan_id}"),
      "plan_kind" => plan_id,
      "plan_authority" => "phase2_evidence_planning_only",
      "does_not_collect_live_evidence" => true,
      "does_not_read_evidence_files" => true,
      "does_not_call_providers" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_enable_production" => true,
      "provider_plans" => entries,
      "live_evidence_status" => "not_collected",
      "required_next_step" => "collect provider evidence and validate a completed evidence packet before Phase 4 review"
    }
  end

  defp plan_entry(tier, template_id, claim, runbook, evidence_template) do
    provider_entries = Map.get(claim, "provider_matrix", [])
    runbook_entries = Map.get(runbook, "entries", [])

    %{
      "tier" => tier,
      "template" => template_id,
      "provider_matrix_entry_ids" => Enum.map(provider_entries, &Map.get(&1, "id")),
      "tracker_kinds" => provider_entries |> Enum.map(&value_at(&1, ["tracker", "kind"])) |> Enum.uniq(),
      "repo_provider_kinds" => provider_entries |> Enum.map(&value_at(&1, ["repo_provider", "kind"])) |> Enum.uniq(),
      "side_effect_modes" => provider_entries |> Enum.map(&Map.get(&1, "side_effect_mode")) |> Enum.uniq(),
      "production_claim" => claim,
      "evidence_runbook" => runbook,
      "evidence_packet_template" => evidence_template,
      "scenario_count" => scenario_count(runbook_entries),
      "live_evidence_status" => "not_collected",
      "read_only_preflight" => read_only_preflight(template_id),
      "evidence_packet_required_before_review" => true,
      "does_not_collect_live_evidence" => true,
      "does_not_enable_production" => true
    }
  end

  defp read_only_preflight(template_id) do
    %{
      "status" => "not_run",
      "does_not_collect_live_evidence" => true,
      "does_not_mutate_workflow_state" => true,
      "does_not_enable_production" => true,
      "commands" => preflight_commands(template_id)
    }
  end

  defp preflight_commands("linear_github_ready") do
    [
      tracker_preflight("linear", "linear/github/opencode", ["LINEAR_API_KEY", "LINEAR_PROJECT_SLUG"]),
      repo_provider_preflight(
        "github",
        "mise exec -- mix repo_provider.smoke --provider github --repo <owner/name> --pr <pr-number> --json",
        [],
        ["gh auth status"],
        ["repo_slug", "change_proposal_number"]
      )
    ]
  end

  defp preflight_commands("tapd_cnb_shadow") do
    [
      tracker_preflight("tapd", "tapd/cnb/opencode", ["TAPD_API_USER", "TAPD_API_PASSWORD", "TAPD_WORKSPACE_ID"]),
      repo_provider_preflight(
        "cnb",
        "mise exec -- mix repo_provider.smoke --provider cnb --repo <owner/name> --pr <pr-number> --json",
        ["CNB_TOKEN"],
        [],
        ["repo_slug", "change_proposal_number"]
      )
    ]
  end

  defp preflight_commands("linear_cnb_shadow") do
    [
      tracker_preflight("linear", "linear/github/opencode", ["LINEAR_API_KEY", "LINEAR_PROJECT_SLUG"]),
      repo_provider_preflight(
        "cnb",
        "mise exec -- mix repo_provider.smoke --provider cnb --repo <owner/name> --pr <pr-number> --json",
        ["CNB_TOKEN"],
        [],
        ["repo_slug", "change_proposal_number"]
      )
    ]
  end

  defp tracker_preflight(provider_kind, template, required_env) do
    %{
      "id" => "#{provider_kind}-tracker-read-only-smoke",
      "target" => "tracker",
      "provider_kind" => provider_kind,
      "command" => "mise exec -- mix tracker.smoke --template #{template} --json",
      "required_env" => required_env,
      "required_auth" => [],
      "required_targets" => [],
      "side_effect_mode" => "read_only",
      "requires_write_confirmation" => false,
      "does_not_write" => true
    }
  end

  defp repo_provider_preflight(provider_kind, command, required_env, required_auth, required_targets) do
    %{
      "id" => "#{provider_kind}-repo-provider-read-only-smoke",
      "target" => "repo_provider",
      "provider_kind" => provider_kind,
      "command" => command,
      "required_env" => required_env,
      "required_auth" => required_auth,
      "required_targets" => required_targets,
      "side_effect_mode" => "read_only",
      "requires_destructive_flag" => false,
      "does_not_write" => true
    }
  end

  defp scenario_count(runbook_entries) do
    runbook_entries
    |> Enum.flat_map(&(Map.get(&1, "scenario_checklist", []) || []))
    |> length()
  end

  defp invalid(errors) do
    %{
      code: @error_code,
      message: "Coding PR Delivery Phase 2 evidence plan is invalid.",
      errors: errors
    }
  end

  defp issue(code, path, message, extra \\ %{}) do
    %{
      code: code,
      path: path,
      message: message
    }
    |> Map.merge(extra)
  end

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
