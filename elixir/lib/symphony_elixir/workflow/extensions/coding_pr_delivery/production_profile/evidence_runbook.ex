defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidenceRunbook do
  @moduledoc """
  Builds bounded Phase 2 evidence collection runbooks for production claims.

  The runbook is a deterministic projection over an already valid production
  claim. It names scenarios and evidence destinations; it does not call tracker,
  repo-provider, agent-provider, or storage backends.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.Claim
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  @schema "coding_pr_delivery.production_evidence_runbook.v1"
  @base_scenarios [
    {"review_handoff_success", "Successful review handoff"},
    {"review_handoff_missing_validation_block", "Blocked handoff for missing validation"},
    {"review_handoff_missing_change_proposal_block", "Blocked handoff for missing PR/MR linkage"},
    {"review_handoff_recovered_after_evidence", "Blocked handoff recovered after evidence is recorded"},
    {"stale_head_or_workpad_block_and_recovery", "Stale head or stale Workpad block and recovery"},
    {"provider_outage_block_and_recovery", "Tracker or repo-provider outage block and recovery"},
    {"duplicate_callback_replay_rejection", "Duplicate typed-tool callback or replay rejection"}
  ]
  @reconciliation_scenarios [
    {"reconciliation_pending_checks", "Pending checks do not move ready-to-land"},
    {"reconciliation_failing_checks", "Failing checks do not move ready-to-land"},
    {"reconciliation_provider_retry", "Provider retry or downgrade is bounded"},
    {"reconciliation_noop_repeat", "Repeated reconciliation is a no-op"},
    {"reconciliation_state_precondition_conflict", "State precondition conflict fails closed"},
    {"reconciliation_queue_drop_behavior", "Queue/drop behavior is observable"},
    {"operator_one_shot_recovery", "Operator one-shot recovery path is recorded"}
  ]

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: result()
  def build(claim) when is_map(claim) do
    with {:ok, normalized_claim} <- Claim.validate(claim) do
      {:ok, runbook(normalized_claim)}
    end
  end

  def build(_claim), do: Claim.validate(:invalid)

  defp runbook(claim) do
    entries = Map.get(claim, "provider_matrix", [])
    governance_packets = Map.get(claim, "production_governance", [])
    exceptions = Map.get(claim, "typed_tool_exceptions", [])

    %{
      "schema" => @schema,
      "profile_instance_id" => Map.get(claim, "profile_instance_id"),
      "claim_authority" => "diagnostic_runbook_only",
      "does_not_execute_providers" => true,
      "entries" => Enum.map(entries, &entry_runbook(&1, governance_packets, exceptions))
    }
  end

  defp entry_runbook(entry, governance_packets, exceptions) do
    entry_id = Map.get(entry, "id")
    governance = Enum.find(governance_packets, &(value_at(&1, ["provider_matrix_entry_id"]) == entry_id)) || %{}
    matching_exceptions = Enum.filter(exceptions, &exception_matches_entry?(&1, entry))
    side_effect_mode = Map.get(entry, "side_effect_mode")

    %{
      "entry_id" => entry_id,
      "workflow_profile" => Map.get(entry, "workflow_profile"),
      "tracker" => Map.get(entry, "tracker"),
      "repo_provider" => Map.get(entry, "repo_provider"),
      "agent_provider" => Map.get(entry, "agent_provider"),
      "repository_class" => Map.get(entry, "repository_class"),
      "side_effect_mode" => side_effect_mode,
      "evidence_files" => evidence_files(entry, governance, matching_exceptions),
      "typed_tool_inventory" => Map.get(entry, "typed_tool_inventory"),
      "topology" => Map.get(entry, "deployment_topology"),
      "rollback" => rollback(entry, governance),
      "scenario_checklist" => scenarios_for(entry),
      "collection_steps" => collection_steps(entry, matching_exceptions),
      "shadow_requirements" => shadow_requirements(side_effect_mode),
      "ready_to_land_requirements" => ready_to_land_requirements(entry),
      "non_claims" => non_claims(entry)
    }
  end

  defp evidence_files(entry, governance, exceptions) do
    %{
      "provider_matrix" => Map.get(entry, "evidence_files", []),
      "production_governance" => Map.get(governance, "evidence_files", []),
      "typed_tool_exceptions" => exceptions |> Enum.flat_map(&Map.get(&1, "real_integration_evidence", [])) |> Enum.uniq()
    }
  end

  defp rollback(entry, governance) do
    %{
      "provider_matrix" => Map.get(entry, "rollback"),
      "production_governance" => Map.get(governance, "rollback")
    }
  end

  defp scenarios_for(entry) do
    @base_scenarios
    |> Kernel.++(mode_scenarios(Map.get(entry, "side_effect_mode")))
    |> Kernel.++(@reconciliation_scenarios)
    |> Enum.uniq_by(fn {id, _title} -> id end)
    |> Enum.map(fn {id, title} ->
      %{
        "id" => id,
        "title" => title,
        "required" => true,
        "evidence_status" => "pending_live_evidence"
      }
    end)
  end

  defp mode_scenarios("ready_to_land_write") do
    [
      {"reconciliation_ready_to_land_write", "Ready-to-land write under approved transition readiness gates"}
    ]
  end

  defp mode_scenarios("shadow_no_write") do
    [
      {"shadow_decision_chain", "Shadow/no-write decision chain emits diagnostic-only evidence"},
      {"shadow_isolation", "Shadow output is isolated from canonical authority surfaces"}
    ]
  end

  defp mode_scenarios("review_handoff_write") do
    [
      {"review_handoff_write_boundary", "Review handoff write stays inside approved tracker/repo-provider surfaces"}
    ]
  end

  defp mode_scenarios(_mode), do: []

  defp collection_steps(entry, exceptions) do
    [
      step("validate_production_claim", "Run ProductionProfile.Claim.validate/1 for this packet."),
      step("capture_typed_tool_inventory", "Record exact tracker, repo-core, and repo-provider typed-tool inventory."),
      step("capture_governance_packet", "Attach structured-plan durability, retention, tombstone, scrubbing, and rollback evidence."),
      step("run_provider_scenarios", "Execute and attach live evidence for every scenario in scenario_checklist."),
      step("verify_rollback", "Record rollback owner, gates, and non-destructive rollback behavior."),
      step("attach_exceptions", exception_step_text(exceptions))
    ]
    |> maybe_append_shadow_step(Map.get(entry, "side_effect_mode"))
    |> maybe_append_ready_to_land_step(entry)
  end

  defp step(id, title), do: %{"id" => id, "title" => title, "status" => "pending_live_evidence"}

  defp exception_step_text([]), do: "No non-typed tool exception evidence is linked for this provider entry."

  defp exception_step_text(_exceptions) do
    "Validate scoped non-typed tool exception evidence and confirm it remains outside raw provider passthrough."
  end

  defp maybe_append_shadow_step(steps, "shadow_no_write") do
    steps ++ [step("verify_shadow_isolation", "Confirm shadow evidence uses the no-production-write prefix, run id, and diagnostic-only destinations.")]
  end

  defp maybe_append_shadow_step(steps, _mode), do: steps

  defp maybe_append_ready_to_land_step(steps, entry) do
    if Map.get(entry, "side_effect_mode") == "ready_to_land_write" do
      steps ++ [step("verify_transition_readiness_gate", "Confirm transition readiness is required before any ready-to-land write.")]
    else
      steps
    end
  end

  defp shadow_requirements("shadow_no_write") do
    %{
      "prefix" => OneShotContract.shadow_prefix(),
      "authority" => OneShotContract.shadow_authority(),
      "canonical_authority" => false,
      "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
    }
  end

  defp shadow_requirements(_mode), do: nil

  defp ready_to_land_requirements(%{"side_effect_mode" => "ready_to_land_write"} = entry) do
    gates = Map.get(entry, "structured_plan_gates", %{})

    %{
      "transition_readiness_required" => Map.get(gates, Gates.transition_readiness_required_gate_key()) == true,
      "transition_readiness_gate" => Gates.transition_readiness_required_gate_key()
    }
  end

  defp ready_to_land_requirements(_entry), do: nil

  defp non_claims(entry) do
    topology = Map.get(entry, "deployment_topology", %{})

    case Map.get(topology, "mode") do
      "singleton" ->
        ["multi_node_ownership", "automatic_durable_replay", "automatic_cold_start_provider_rebuild"]

      "distributed_lock" ->
        ["automatic_cold_start_provider_rebuild_unless_evidenced"]

      "external_queue" ->
        ["automatic_cold_start_provider_rebuild_unless_evidenced"]

      _mode ->
        ["unvalidated_topology_claims"]
    end
  end

  defp exception_matches_entry?(exception, entry) when is_map(exception) and is_map(entry) do
    value_at(exception, ["workflow_profile"]) == Map.get(entry, "workflow_profile") and
      value_at(exception, ["tracker", "kind"]) == value_at(entry, ["tracker", "kind"]) and
      value_at(exception, ["repo_provider", "kind"]) == value_at(entry, ["repo_provider", "kind"]) and
      value_at(exception, ["agent_provider", "kind"]) == value_at(entry, ["agent_provider", "kind"]) and
      value_at(exception, ["repository_class"]) == Map.get(entry, "repository_class")
  end

  defp exception_matches_entry?(_exception, _entry), do: false

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
