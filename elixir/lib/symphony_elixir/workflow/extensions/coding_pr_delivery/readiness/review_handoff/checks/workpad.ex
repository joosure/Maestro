defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Workpad do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks.Support
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Values

  import ResultBuilder,
    only: [
      check_key: 1,
      failed_check: 4,
      missing_check: 4,
      observed_evidence_code: 1,
      passed_check: 3,
      reason_code: 1,
      stale_check: 4
    ]

  @workpad_key Evidence.workpad_key()
  @source_key Evidence.source_key()
  @status_key Evidence.status_key()
  @url_key Evidence.url_key()
  @updated_at_key Evidence.updated_at_key()
  @typed_tool_observed_source Values.typed_tool_observed_source()
  @tracker_observed_source Values.tracker_observed_source()
  @created_status Values.created_status()
  @updated_status Values.updated_status()
  @passing_workpad_statuses [@created_status, @updated_status]

  @spec check(map() | term(), [map() | term()]) :: map()
  def check(workpad, readiness_observations) do
    cond do
      not is_map(workpad) or map_size(workpad) == 0 ->
        missing_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_missing),
          "A backend-observed workpad handoff record is required.",
          Support.observed(workpad, @workpad_key)
        )

      not trusted_workpad_record?(workpad) ->
        failed_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_untrusted),
          "Workpad readiness requires a successful backend-observed workpad write, not agent-declared section completion.",
          Support.observed(workpad, @workpad_key)
        )

      stale_workpad_record?(workpad, readiness_observations) ->
        stale_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_stale),
          "The workpad handoff record must be updated after the latest repository, change-proposal, validation, check, or feedback evidence.",
          Support.observed(workpad, @workpad_key)
        )

      true ->
        passed_check(check_key(:workpad_recorded), observed_evidence_code(:workpad_recorded), Support.observed(workpad, @workpad_key))
    end
  end

  defp trusted_workpad_record?(workpad) when is_map(workpad) do
    Map.get(workpad, @source_key) in [@typed_tool_observed_source, @tracker_observed_source] and
      Map.get(workpad, @status_key) in @passing_workpad_statuses and
      not is_nil(workpad_recorded_at(workpad)) and
      (Support.present?(Map.get(workpad, Evidence.workpad_id_key())) or
         Support.present?(Map.get(workpad, @url_key)))
  end

  defp stale_workpad_record?(workpad, readiness_observations) do
    recorded_at = workpad_recorded_at(workpad)
    latest_evidence_at = Support.latest_observed_at(readiness_observations)

    case {recorded_at, latest_evidence_at} do
      {%DateTime{} = recorded, %DateTime{} = latest} -> DateTime.compare(recorded, latest) == :lt
      _timestamps -> false
    end
  end

  defp workpad_recorded_at(workpad) when is_map(workpad) do
    workpad
    |> Map.get(@updated_at_key)
    |> parse_datetime()
    |> case do
      %DateTime{} = updated_at -> updated_at
      nil -> Support.parsed_observed_at(workpad)
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil
end
