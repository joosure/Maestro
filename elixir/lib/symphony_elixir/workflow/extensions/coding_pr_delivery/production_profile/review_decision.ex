defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewDecision do
  @moduledoc """
  Builds a bounded reviewer-facing decision projection for production packets.

  The decision is derived from `ReviewPacket.validate/1`. It summarizes whether
  a packet is ready for review or blocked, plus provider scope, evidence counts,
  explicit non-claims, and bounded blocker metadata. It intentionally omits raw
  evidence payloads and does not read files, call providers, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ReviewPacket

  @schema "coding_pr_delivery.production_review_decision.v1"

  @spec build(map()) :: {:ok, map()}
  def build(packet) when is_map(packet) do
    case ReviewPacket.validate(packet) do
      {:ok, review_packet} ->
        {:ok, ready_decision(review_packet)}

      {:error, reason} ->
        {:ok, blocked_decision(packet, reason)}
    end
  end

  def build(packet) do
    {:ok,
     %{
       "schema" => @schema,
       "status" => "blocked",
       "review_packet_id" => nil,
       "profile_instance_id" => nil,
       "provider_entries" => [],
       "evidence_summary" => %{"scenario_evidence_count" => 0, "non_claim_acknowledgement_count" => 0},
       "owner_signoffs" => [],
       "blockers" => [blocker(%{code: "invalid_type", path: [], message: "Review packet must be an object."})],
       "does_not_enable_production" => true,
       "raw_evidence_payload_included" => false,
       "input_type" => inspect(packet)
     }}
  end

  defp ready_decision(review_packet) do
    evidence_packet = Map.get(review_packet, "evidence_packet", %{})

    %{
      "schema" => @schema,
      "status" => "ready_for_approval",
      "review_packet_id" => Map.get(review_packet, "review_packet_id"),
      "profile_instance_id" => Map.get(review_packet, "profile_instance_id"),
      "provider_entries" => provider_entries(evidence_packet),
      "evidence_summary" => evidence_summary(evidence_packet),
      "owner_signoffs" => owner_signoffs(review_packet),
      "blockers" => [],
      "does_not_enable_production" => true,
      "raw_evidence_payload_included" => false
    }
  end

  defp blocked_decision(packet, reason) do
    %{
      "schema" => @schema,
      "status" => "blocked",
      "review_packet_id" => value_at(packet, ["review_packet_id"]),
      "profile_instance_id" => value_at(packet, ["evidence_packet", "production_claim", "profile_instance_id"]),
      "provider_entries" => [],
      "evidence_summary" => %{
        "scenario_evidence_count" => count_at(packet, ["evidence_packet", "scenario_evidence"]),
        "non_claim_acknowledgement_count" => count_at(packet, ["evidence_packet", "non_claim_acknowledgements"])
      },
      "owner_signoffs" => owner_signoffs(packet),
      "blockers" => blockers(reason),
      "does_not_enable_production" => true,
      "raw_evidence_payload_included" => false
    }
  end

  defp provider_entries(evidence_packet) do
    evidence_packet
    |> value_at(["runbook", "entries"])
    |> case do
      entries when is_list(entries) ->
        Enum.map(entries, &provider_entry/1)

      _missing ->
        []
    end
  end

  defp provider_entry(entry) when is_map(entry) do
    %{
      "entry_id" => Map.get(entry, "entry_id"),
      "workflow_profile" => Map.get(entry, "workflow_profile"),
      "tracker" => provider_kind(Map.get(entry, "tracker")),
      "repo_provider" => provider_kind(Map.get(entry, "repo_provider")),
      "agent_provider" => provider_kind(Map.get(entry, "agent_provider")),
      "side_effect_mode" => Map.get(entry, "side_effect_mode"),
      "topology_mode" => value_at(entry, ["topology", "mode"]),
      "non_claims" => Map.get(entry, "non_claims", [])
    }
  end

  defp evidence_summary(evidence_packet) do
    %{
      "scenario_evidence_count" => count_at(evidence_packet, ["scenario_evidence"]),
      "non_claim_acknowledgement_count" => count_at(evidence_packet, ["non_claim_acknowledgements"])
    }
  end

  defp owner_signoffs(packet) do
    packet
    |> value_at(["owner_signoffs"])
    |> case do
      signoffs when is_list(signoffs) ->
        Enum.map(signoffs, fn signoff ->
          %{
            "role" => value_at(signoff, ["role"]),
            "owner" => value_at(signoff, ["owner"]),
            "decision" => value_at(signoff, ["decision"])
          }
        end)

      _missing ->
        []
    end
  end

  defp provider_kind(%{"kind" => kind}), do: %{"kind" => kind}
  defp provider_kind(_provider), do: %{"kind" => nil}

  defp blockers(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &blocker/1)

  defp blocker(error) when is_map(error) do
    %{
      "code" => Map.get(error, :code) || Map.get(error, "code") || "invalid",
      "path" => Map.get(error, :path) || Map.get(error, "path") || [],
      "message" => Map.get(error, :message) || Map.get(error, "message") || "Review packet is invalid."
    }
  end

  defp count_at(map, path) do
    case value_at(map, path) do
      values when is_list(values) -> length(values)
      _missing -> 0
    end
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
