defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder do
  @moduledoc """
  Result and check envelope builder for Coding PR Delivery review handoff.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract, as: Evidence
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Target
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.{Envelope, Result, Values}

  @policy_id Contract.coding_pr_delivery_policy_id()
  @schema Contract.schema()
  @schema_key Envelope.schema_key()
  @policy_id_key Envelope.policy_id_key()
  @status_key Evidence.status_key()
  @remediation_actions_key Contract.remediation_actions_key()
  @target_state_key Result.target_state_key()
  @capability_gaps_key Result.capability_gaps_key()
  @downgrades_key Result.downgrades_key()
  @error_code_key Result.error_code_key()
  @reason_code_key Result.reason_code_key()
  @reason_codes_key Result.reason_codes_key()
  @code_key Result.code_key()
  @detail_key Result.detail_key()
  @passed_status Values.passed_status()
  @blocked_status Values.blocked_status()
  @missing_status Values.missing_status()
  @failed_status Values.failed_status()
  @stale_status Values.stale_status()
  @review_handoff_not_ready_error Contract.not_ready_error()

  @spec passed_result(map() | struct() | nil, String.t() | nil, [map()]) :: map()
  def passed_result(workflow, target_state_name, checks) do
    base_result(workflow, target_state_name, checks)
    |> Map.put(@status_key, @passed_status)
  end

  @spec blocked_result(map() | struct() | nil, String.t() | nil, [map()]) :: map()
  def blocked_result(workflow, target_state_name, checks) do
    failing_checks = Enum.reject(checks, &passed_check?/1)

    base_result(workflow, target_state_name, checks)
    |> Map.put(@status_key, @blocked_status)
    |> Map.put(@error_code_key, @review_handoff_not_ready_error)
    |> Map.put(@reason_codes_key, failing_checks |> Enum.map(&Map.get(&1, @reason_code_key)) |> Enum.reject(&is_nil/1) |> Enum.uniq())
    |> Map.put(ReadinessContract.missing_evidence_key(), Enum.map(failing_checks, &missing_entry/1))
    |> Map.put(@remediation_actions_key, Remediation.actions(failing_checks))
  end

  @spec invalid_options_result(map() | struct() | nil, map()) :: map()
  def invalid_options_result(workflow, reason) when is_map(reason) do
    blocked_result(workflow, nil, [
      failed_check(
        check_key(:options_valid),
        reason_code(:options_invalid),
        "Review handoff options must be a keyword list.",
        ["#{@schema}.options.value_type=#{Map.get(reason, :value_type, "term")}"]
      )
    ])
  end

  @spec passed_check(String.t(), String.t() | nil, [String.t()]) :: map()
  def passed_check(key, observed_evidence, observed) do
    check(key, @passed_status, nil, observed_evidence, observed)
  end

  @spec missing_check(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def missing_check(key, reason_code, detail, observed) do
    check(key, @missing_status, reason_code, detail, observed)
  end

  @spec failed_check(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def failed_check(key, reason_code, detail, observed) do
    check(key, @failed_status, reason_code, detail, observed)
  end

  @spec stale_check(String.t(), String.t(), String.t(), [String.t()]) :: map()
  def stale_check(key, reason_code, detail, observed) do
    check(key, @stale_status, reason_code, detail, observed)
  end

  @spec check_key(atom()) :: String.t()
  def check_key(key), do: Contract.check_key(key)

  @spec reason_code(atom()) :: String.t()
  def reason_code(key), do: Contract.reason_code(key)

  @spec observed_evidence_code(atom()) :: String.t()
  def observed_evidence_code(key), do: Contract.observed_evidence_code(key)

  @spec passed_result?(map()) :: boolean()
  def passed_result?(result) when is_map(result), do: Map.get(result, @status_key) == @passed_status
  def passed_result?(_result), do: false

  @spec passed_check?(map()) :: boolean()
  def passed_check?(check) when is_map(check), do: Map.get(check, @status_key) == @passed_status
  def passed_check?(_check), do: false

  defp base_result(workflow, target_state_name, checks) do
    %{
      @schema_key => @schema,
      @policy_id_key => @policy_id,
      ReadinessContract.gate_key() => ReadinessContract.human_review_gate(),
      @target_state_key => target_state_name,
      ReadinessContract.checks_key() => checks,
      @capability_gaps_key => [],
      @downgrades_key => [],
      ReadinessContract.observed_evidence_key() => observed_evidence(checks)
    }
    |> Map.merge(
      workflow
      |> Target.workflow_profile_ref()
      |> RouteRef.string_fields(CodingPrDelivery.review_route_key())
    )
    |> drop_nil_values()
  end

  defp check(key, status, reason_code, required_evidence, observed_evidence) do
    %{
      ReadinessContract.key_key() => key,
      @status_key => status,
      @reason_code_key => reason_code,
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
    |> drop_nil_values()
  end

  defp missing_entry(check) do
    %{
      @code_key => Map.fetch!(check, @reason_code_key),
      @detail_key => Map.fetch!(check, ReadinessContract.required_evidence_key())
    }
  end

  defp observed_evidence(checks) do
    checks
    |> Enum.flat_map(&List.wrap(Map.get(&1, ReadinessContract.observed_evidence_key())))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp drop_nil_values(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
