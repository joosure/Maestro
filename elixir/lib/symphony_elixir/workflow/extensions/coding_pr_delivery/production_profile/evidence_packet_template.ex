defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.EvidencePacketTemplate do
  @moduledoc """
  Builds Phase 2 evidence-packet fill templates from accepted production claims.

  The template enumerates the completed evidence packet shape required after
  live provider or shadow runs. It does not mark evidence as passed, read
  evidence files, call providers, mutate workflow state, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.{
    Claim,
    EvidenceRunbook
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.OneShot.Contract, as: OneShotContract

  @schema "coding_pr_delivery.production_evidence_packet_template.v1"
  @completed_packet_schema "coding_pr_delivery.production_evidence_packet.v1"
  @shadow_mode OneShotContract.shadow_mode()

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: result()
  def build(claim) when is_map(claim) do
    with {:ok, normalized_claim} <- Claim.validate(claim),
         {:ok, runbook} <- EvidenceRunbook.build(normalized_claim) do
      {:ok, template(normalized_claim, runbook)}
    end
  end

  def build(claim), do: Claim.validate(claim)

  defp template(claim, runbook) do
    entries = Map.get(runbook, "entries", [])

    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "profile_instance_id" => Map.get(claim, "profile_instance_id"),
      "template_authority" => "evidence_packet_shape_only",
      "does_not_collect_live_evidence" => true,
      "production_claim" => claim,
      "runbook" => runbook,
      "scenario_evidence_requirements" => scenario_requirements(entries),
      "non_claim_acknowledgement_requirements" => non_claim_acknowledgement_requirements(entries)
    }
  end

  defp scenario_requirements(entries) do
    Enum.flat_map(entries, fn entry ->
      entry
      |> Map.get("scenario_checklist", [])
      |> Enum.map(&scenario_requirement(entry, &1))
    end)
  end

  defp scenario_requirement(entry, scenario) do
    entry_id = Map.get(entry, "entry_id")

    %{
      "provider_matrix_entry_id" => entry_id,
      "scenario_id" => Map.get(scenario, "id"),
      "scenario_title" => Map.get(scenario, "title"),
      "required_status" => "passed",
      "required_evidence_kind" => evidence_kind(entry),
      "evidence_files" => ["evidence/live/#{entry_id}/#{Map.get(scenario, "id")}.md"],
      "fields_to_complete" => ["collector", "collected_at", "evidence_files"],
      "shadow" => shadow_requirement(entry),
      "no_write_flags" => no_write_flags(entry)
    }
  end

  defp evidence_kind(%{"side_effect_mode" => @shadow_mode}), do: "shadow_integration"
  defp evidence_kind(_entry), do: "real_integration"

  defp shadow_requirement(%{"side_effect_mode" => @shadow_mode} = entry) do
    runbook_shadow = Map.get(entry, "shadow_requirements") || %{}

    %{
      "prefix" => OneShotContract.shadow_prefix(),
      "run_id" => Map.get(runbook_shadow, "run_id") || "fill-from-shadow-run",
      "authority" => OneShotContract.shadow_authority(),
      "canonical_authority" => false,
      "allowed_destinations" => OneShotContract.shadow_allowed_destinations()
    }
  end

  defp shadow_requirement(_entry), do: nil

  defp no_write_flags(%{"side_effect_mode" => @shadow_mode}) do
    %{
      "production_write_performed" => false,
      "canonical_surface_mutated" => false
    }
  end

  defp no_write_flags(_entry), do: nil

  defp non_claim_acknowledgement_requirements(entries) do
    Enum.map(entries, fn entry ->
      %{
        "provider_matrix_entry_id" => Map.get(entry, "entry_id"),
        "non_claims" => Map.get(entry, "non_claims", []),
        "fields_to_complete" => ["owner", "acknowledged_at"]
      }
    end)
  end
end
