defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatusTemplate do
  @moduledoc """
  Builds observation-status fill templates from accepted operator apply records.

  The template is a shape-only handoff for post-apply observation tracking. It
  validates the operator apply record first, then projects the status fields
  operators must complete during the approved observation window. It does not
  inspect providers, mutate workflow state, apply settings, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.OperatorApplyRecord

  @schema "coding_pr_delivery.production_observation_status_template.v1"
  @completed_packet_schema "coding_pr_delivery.production_observation_status.v1"
  @status_options ["in_progress", "passed", "failed"]
  @allowed_evidence_ref_prefixes ["evidence/", "https://", "http://"]

  @type result :: {:ok, map()} | {:error, map()}

  @spec build(map()) :: result()
  def build(apply_record) when is_map(apply_record) do
    with {:ok, normalized_record} <- OperatorApplyRecord.validate(apply_record) do
      {:ok, template(apply_record, normalized_record)}
    end
  end

  def build(apply_record), do: OperatorApplyRecord.validate(apply_record)

  defp template(apply_record, normalized_record) do
    observation_window = value_at(normalized_record, ["observation_start", "observation_window"])

    %{
      "schema" => @schema,
      "completed_packet_schema" => @completed_packet_schema,
      "profile_instance_id" => value_at(normalized_record, ["profile_instance_id"]),
      "review_packet_id" => value_at(normalized_record, ["review_packet_id"]),
      "enablement_request_id" => value_at(normalized_record, ["enablement_request_id"]),
      "apply_record_id" => value_at(normalized_record, ["apply_record_id"]),
      "template_authority" => "observation_status_shape_only",
      "records_observation_only" => true,
      "does_not_enable_production" => true,
      "status_options" => @status_options,
      "allowed_evidence_ref_prefixes" => @allowed_evidence_ref_prefixes,
      "observation_status_field_template" => %{
        "observation_status_id" => "fill-observation-status-id",
        "operator_apply_record" => apply_record,
        "observed_by" => "fill-observer",
        "observed_at" => "fill-observed-at",
        "status" => "in_progress",
        "observation_window" => observation_window,
        "criteria_results" => criteria_results(observation_window),
        "no_write_observation" => no_write_observation(normalized_record)
      },
      "fields_to_complete" => fields_to_complete(normalized_record)
    }
  end

  defp criteria_results(%{"success_criteria" => criteria}) when is_list(criteria) do
    Enum.map(criteria, fn criterion ->
      %{
        "criterion" => criterion,
        "status" => "in_progress",
        "observed_at" => "fill-observed-at",
        "allowed_evidence_ref_prefixes" => @allowed_evidence_ref_prefixes,
        "evidence_files" => [evidence_file(criterion)]
      }
    end)
  end

  defp criteria_results(_window), do: []

  defp evidence_file(criterion) do
    "evidence/observation/#{criterion_slug(criterion)}.md"
  end

  defp criterion_slug(criterion) when is_binary(criterion) do
    criterion
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "criterion"
      slug -> slug
    end
  end

  defp criterion_slug(_criterion), do: "criterion"

  defp no_write_observation(%{"applied_scope" => %{"side_effect_mode" => "shadow_no_write"}}) do
    %{
      "production_write_performed" => false,
      "canonical_surface_mutated" => false
    }
  end

  defp no_write_observation(_normalized_record), do: nil

  defp fields_to_complete(normalized_record) do
    base = [
      "observation_status_id",
      "observed_by",
      "observed_at",
      "status",
      "criteria_results[].status",
      "criteria_results[].observed_at",
      "criteria_results[].evidence_files"
    ]

    if value_at(normalized_record, ["applied_scope", "side_effect_mode"]) == "shadow_no_write" do
      base ++
        [
          "no_write_observation.production_write_performed",
          "no_write_observation.canonical_surface_mutated"
        ]
    else
      base
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
