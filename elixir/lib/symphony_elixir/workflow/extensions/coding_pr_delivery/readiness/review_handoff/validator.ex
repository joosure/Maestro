defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Validator do
  @moduledoc """
  Thin orchestration service for `coding_pr_delivery.review_handoff.v1`.

  The registered policy facade delegates here, while target resolution,
  evidence sourcing, check rules, and result construction live in sibling
  modules. This keeps the exported plugin boundary stable for a future external
  plugin package.
  """

  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Checks
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Context
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.EvidenceSource
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.ResultBuilder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Target

  @policy_id Contract.coding_pr_delivery_policy_id()
  @schema Contract.schema()
  @issue_snapshot_required_detail "Structured tracker issue snapshot is required."

  @type validation_result :: :ok | {:error, {:review_handoff_not_ready, map()}}

  @spec policy_id() :: String.t()
  def policy_id, do: @policy_id

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec governed_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  def governed_target?(workflow, target_state_name), do: review_target?(workflow, target_state_name)

  @spec review_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  def review_target?(workflow, target_state_name), do: Target.review_target?(workflow, target_state_name)

  @spec validate(Effective.t() | map() | nil, map(), keyword()) :: validation_result()
  def validate(workflow, issue, opts \\ [])

  def validate(workflow, issue, opts) do
    case Options.normalize(opts) do
      {:ok, opts} -> validate_normalized(workflow, issue, opts)
      {:error, reason} -> {:error, {:review_handoff_not_ready, ResultBuilder.invalid_options_result(workflow, reason)}}
    end
  end

  defp validate_normalized(workflow, issue, opts) when is_map(issue) do
    context = Context.build(opts)
    target_state_name = Context.target_state_name(context)

    if review_target?(workflow, target_state_name) do
      evidence = EvidenceSource.evidence_for_issue(issue, opts)
      result = validate_evidence(workflow, issue, evidence, opts)

      if ResultBuilder.passed_result?(result) do
        :ok
      else
        {:error, {:review_handoff_not_ready, result}}
      end
    else
      :ok
    end
  end

  defp validate_normalized(workflow, _issue, opts) do
    context = Context.build(opts)
    target_state_name = Context.target_state_name(context)

    if review_target?(workflow, target_state_name) do
      {:error,
       {:review_handoff_not_ready,
        ResultBuilder.blocked_result(workflow, target_state_name, [
          ResultBuilder.missing_check(
            ResultBuilder.check_key(:issue_snapshot),
            ResultBuilder.reason_code(:issue_snapshot_missing),
            @issue_snapshot_required_detail,
            []
          )
        ])}}
    else
      :ok
    end
  end

  @spec validate_evidence(Effective.t() | map() | nil, map(), map(), keyword()) :: map()
  def validate_evidence(workflow, issue, evidence, opts \\ [])

  def validate_evidence(workflow, issue, evidence, opts) when is_map(issue) and is_map(evidence) do
    case Options.normalize(opts) do
      {:ok, opts} ->
        context = Context.build(opts)
        target_state_name = Context.target_state_name(context)
        observations = EvidenceSource.normalized_observations(evidence, issue)
        checks = Checks.checks(workflow, issue, observations, opts)

        if Enum.all?(checks, &ResultBuilder.passed_check?/1) do
          ResultBuilder.passed_result(workflow, target_state_name, checks)
        else
          ResultBuilder.blocked_result(workflow, target_state_name, checks)
        end

      {:error, reason} ->
        ResultBuilder.invalid_options_result(workflow, reason)
    end
  end

  def validate_evidence(workflow, _issue, _evidence, opts) do
    case Options.normalize(opts) do
      {:ok, opts} ->
        context = Context.build(opts)

        ResultBuilder.blocked_result(workflow, Context.target_state_name(context), [
          ResultBuilder.missing_check(
            ResultBuilder.check_key(:issue_snapshot),
            ResultBuilder.reason_code(:issue_snapshot_missing),
            @issue_snapshot_required_detail,
            []
          )
        ])

      {:error, reason} ->
        ResultBuilder.invalid_options_result(workflow, reason)
    end
  end
end
