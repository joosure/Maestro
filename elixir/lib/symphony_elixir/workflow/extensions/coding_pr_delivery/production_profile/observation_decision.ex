defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationDecision do
  @moduledoc """
  Builds bounded reviewer-facing decisions from observation status records.

  The decision summarizes whether post-apply observation is passed, failed, in
  progress, or blocked. It intentionally omits raw evidence payloads and does
  not inspect providers, mutate workflow state, apply settings, or enable gates.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.ProductionProfile.ObservationStatus

  @schema "coding_pr_delivery.production_observation_decision.v1"

  @spec build(map()) :: {:ok, map()}
  def build(status) when is_map(status) do
    case ObservationStatus.validate(status) do
      {:ok, observation_status} ->
        {:ok, decision(observation_status)}

      {:error, reason} ->
        {:ok, blocked_decision(status, reason)}
    end
  end

  def build(status) do
    {:ok,
     %{
       "schema" => @schema,
       "status" => "blocked",
       "observation_status_id" => nil,
       "profile_instance_id" => nil,
       "review_packet_id" => nil,
       "enablement_request_id" => nil,
       "apply_record_id" => nil,
       "criteria_summary" => %{"passed" => 0, "failed" => 0, "in_progress" => 0, "total" => 0},
       "no_write_observation" => nil,
       "blockers" => [blocker(%{code: "invalid_type", path: [], message: "Observation status must be an object."})],
       "records_observation_only" => true,
       "does_not_enable_production" => true,
       "raw_evidence_payload_included" => false,
       "input_type" => inspect(status)
     }}
  end

  defp decision(%{"status" => status} = observation_status) do
    %{
      "schema" => @schema,
      "status" => decision_status(status),
      "observation_status_id" => Map.get(observation_status, "observation_status_id"),
      "profile_instance_id" => Map.get(observation_status, "profile_instance_id"),
      "review_packet_id" => Map.get(observation_status, "review_packet_id"),
      "enablement_request_id" => Map.get(observation_status, "enablement_request_id"),
      "apply_record_id" => Map.get(observation_status, "apply_record_id"),
      "observed_by" => Map.get(observation_status, "observed_by"),
      "observed_at" => Map.get(observation_status, "observed_at"),
      "criteria_summary" => criteria_summary(observation_status),
      "no_write_observation" => Map.get(observation_status, "no_write_observation"),
      "blockers" => [],
      "records_observation_only" => true,
      "does_not_enable_production" => true,
      "raw_evidence_payload_included" => false
    }
  end

  defp blocked_decision(status, reason) do
    %{
      "schema" => @schema,
      "status" => "blocked",
      "observation_status_id" => value_at(status, ["observation_status_id"]),
      "profile_instance_id" => value_at(status, ["operator_apply_record", "operator_apply_plan", "profile_instance_id"]),
      "review_packet_id" => value_at(status, ["operator_apply_record", "operator_apply_plan", "review_packet_id"]),
      "enablement_request_id" => value_at(status, ["operator_apply_record", "operator_apply_plan", "enablement_request_id"]),
      "apply_record_id" => value_at(status, ["operator_apply_record", "apply_record_id"]),
      "criteria_summary" => criteria_summary(status),
      "no_write_observation" => value_at(status, ["no_write_observation"]),
      "blockers" => blockers(reason),
      "records_observation_only" => true,
      "does_not_enable_production" => true,
      "raw_evidence_payload_included" => false
    }
  end

  defp decision_status("passed"), do: "observation_passed"
  defp decision_status("failed"), do: "observation_failed"
  defp decision_status("in_progress"), do: "observation_in_progress"
  defp decision_status(_status), do: "blocked"

  defp criteria_summary(status) do
    statuses =
      status
      |> value_at(["criteria_results"])
      |> case do
        results when is_list(results) ->
          results
          |> Enum.filter(&is_map/1)
          |> Enum.map(&value_at(&1, ["status"]))
          |> Enum.filter(&is_binary/1)

        _missing ->
          []
      end

    %{
      "passed" => Enum.count(statuses, &(&1 == "passed")),
      "failed" => Enum.count(statuses, &(&1 == "failed")),
      "in_progress" => Enum.count(statuses, &(&1 == "in_progress")),
      "total" => length(statuses)
    }
  end

  defp blockers(%{errors: errors}) when is_list(errors), do: Enum.map(errors, &blocker/1)

  defp blocker(error) when is_map(error) do
    %{
      "code" => Map.get(error, :code) || Map.get(error, "code") || "invalid",
      "path" => Map.get(error, :path) || Map.get(error, "path") || [],
      "message" => Map.get(error, :message) || Map.get(error, "message") || "Observation status is invalid."
    }
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
