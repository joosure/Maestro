defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ProviderMatrixTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ProviderMatrix
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract.Gates

  test "accepts TAPD + CNB shadow/no-write evidence entries with diagnostic-only metadata" do
    claim = production_claim([shadow_entry("tapd-cnb-shadow", "tapd", "cnb")])

    assert {:ok, %{"provider_matrix" => [entry]}} = ProviderMatrix.validate_claim(claim)

    assert entry["id"] == "tapd-cnb-shadow"
    assert entry["tracker"]["kind"] == "tapd"
    assert entry["repo_provider"]["kind"] == "cnb"
    assert entry["side_effect_mode"] == OneShotContract.shadow_mode()
    assert entry["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert entry["shadow"]["canonical_authority"] == false
  end

  test "accepts Linear + CNB shadow/no-write evidence entries with diagnostic-only metadata" do
    claim = production_claim([shadow_entry("linear-cnb-shadow", "linear", "cnb")])

    assert {:ok, %{"provider_matrix" => [entry]}} = ProviderMatrix.validate_claim(claim)

    assert entry["id"] == "linear-cnb-shadow"
    assert entry["tracker"]["kind"] == "linear"
    assert entry["repo_provider"]["kind"] == "cnb"
    assert entry["side_effect_mode"] == OneShotContract.shadow_mode()
    assert entry["structured_plan_gates"][Gates.transition_readiness_required_gate_key()] == false
    assert entry["deployment_topology"]["mode"] == "singleton"
    assert entry["shadow"]["prefix"] == OneShotContract.shadow_prefix()
    assert entry["shadow"]["authority"] == OneShotContract.shadow_authority()
    assert entry["shadow"]["canonical_authority"] == false
  end

  test "accepts ready-to-land entries only when production gates and ownership are explicit" do
    claim = production_claim([ready_to_land_entry()])

    assert {:ok, %{"provider_matrix" => [entry]}} = ProviderMatrix.validate_claim(claim)

    assert entry["side_effect_mode"] == "ready_to_land_write"
    assert entry["structured_plan_gates"][Gates.transition_readiness_required_gate_key()] == true
    assert entry["deployment_topology"]["mode"] == "distributed_lock"
    assert entry["deployment_topology"]["ownership_proof"] == "redis-lock:workflow:coding-pr-delivery"
  end

  test "rejects claims without provider matrix entries" do
    assert {:error, %{code: "coding_pr_delivery_provider_matrix_invalid", errors: errors}} =
             ProviderMatrix.validate_claim(%{"profile_instance_id" => "claim-1", "provider_matrix" => []})

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["provider_matrix"]))
  end

  test "rejects entries without an explicit side-effect mode" do
    entry = Map.delete(shadow_entry("missing-mode", "linear", "github"), "side_effect_mode")

    assert {:error, %{errors: errors}} = ProviderMatrix.validate_claim(production_claim([entry]))

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["provider_matrix", 0, "side_effect_mode"]))
  end

  test "rejects legacy gate names in provider matrix entries" do
    entry =
      shadow_entry("legacy-gate", "linear", "cnb")
      |> put_in(["structured_plan_gates", "review_handoff_required"], true)

    assert {:error, %{errors: errors}} = ProviderMatrix.validate_claim(production_claim([entry]))

    assert Enum.any?(errors, &(&1.code == "unknown_gate_key" and &1.path == ["provider_matrix", 0, "structured_plan_gates", "review_handoff_required"]))
  end

  test "rejects shadow entries that claim canonical transition authority" do
    entry =
      shadow_entry("shadow-authority", "tapd", "cnb")
      |> put_in(["shadow", "canonical_authority"], true)
      |> put_in(["structured_plan_gates", Gates.transition_readiness_required_gate_key()], true)

    assert {:error, %{errors: errors}} = ProviderMatrix.validate_claim(production_claim([entry]))

    assert Enum.any?(errors, &(&1.code == "invalid_shadow_metadata" and &1.path == ["provider_matrix", 0, "shadow", "canonical_authority"]))

    assert Enum.any?(
             errors,
             &(&1.code == "shadow_not_authoritative" and &1.path == ["provider_matrix", 0, "structured_plan_gates", Gates.transition_readiness_required_gate_key()])
           )
  end

  test "rejects ready-to-land entries without transition readiness enforcement" do
    entry =
      ready_to_land_entry()
      |> put_in(["structured_plan_gates", Gates.transition_readiness_required_gate_key()], false)

    assert {:error, %{errors: errors}} = ProviderMatrix.validate_claim(production_claim([entry]))

    assert Enum.any?(
             errors,
             &(&1.code == "transition_readiness_required" and &1.path == ["provider_matrix", 0, "structured_plan_gates", Gates.transition_readiness_required_gate_key()])
           )
  end

  test "rejects singleton runtime-targeted entries without readiness proof and does not leak raw values" do
    entry =
      shadow_entry("secret-token=ghp_secret", "tapd", "cnb")
      |> update_in(["deployment_topology"], &Map.delete(&1, "readiness_check"))

    assert {:error, %{errors: errors} = error} = ProviderMatrix.validate_claim(production_claim([entry]))

    assert Enum.any?(errors, &(&1.code == "required_field_missing" and &1.path == ["provider_matrix", 0, "deployment_topology", "readiness_check"]))
    refute inspect(error) =~ "ghp_secret"
  end

  defp production_claim(entries) do
    %{
      "profile_instance_id" => "coding_pr_delivery.production.claim",
      "provider_matrix" => entries
    }
  end

  defp shadow_entry(id, tracker, repo_provider) do
    base_entry(id, tracker, repo_provider)
    |> Map.merge(%{
      "side_effect_mode" => OneShotContract.shadow_mode(),
      "structured_plan_gates" => gates(false),
      "deployment_topology" => %{
        "mode" => "singleton",
        "readiness_check" => "Reconciliation.runtime_topology_readiness/1"
      },
      "shadow" => %{
        "prefix" => OneShotContract.shadow_prefix(),
        "run_id" => "shadow-run-1",
        "authority" => OneShotContract.shadow_authority(),
        "canonical_authority" => false,
        "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
      }
    })
  end

  defp ready_to_land_entry do
    base_entry("linear-github-ready", "linear", "github")
    |> Map.merge(%{
      "side_effect_mode" => "ready_to_land_write",
      "structured_plan_gates" => gates(true),
      "deployment_topology" => %{
        "mode" => "distributed_lock",
        "ownership_proof" => "redis-lock:workflow:coding-pr-delivery"
      }
    })
  end

  defp base_entry(id, tracker, repo_provider) do
    %{
      "id" => id,
      "workflow_profile" => %{"kind" => "coding_pr_delivery", "version" => 1},
      "tracker" => %{"kind" => tracker},
      "repo_provider" => %{"kind" => repo_provider},
      "agent_provider" => %{"kind" => "codex"},
      "repository_class" => "single_repo_change_proposal",
      "candidate_discovery" => "runtime_targeted",
      "typed_tool_inventory" => %{
        "tracker" => ["tracker.issue_snapshot", "tracker.move_issue"],
        "repo_core" => ["repo.diff", "repo.head_sha"],
        "repo_provider" => ["repo_provider.change_proposal_snapshot", "repo_provider.change_proposal_checks"]
      },
      "evidence_files" => ["evidence/provider-matrix/#{id}.md"],
      "recovery" => %{"model" => "operator_one_shot"},
      "rollback" => %{
        "owner" => "workflow-runtime",
        "disable_readiness_gate" => Gates.transition_readiness_required_gate_key()
      }
    }
  end

  defp gates(transition_readiness_required) do
    %{
      Gates.enabled_gate_key() => true,
      Gates.render_workpad_gate_key() => true,
      Gates.transition_readiness_required_gate_key() => transition_readiness_required,
      Gates.provider_adapters_enabled_gate_key() => false
    }
  end
end
