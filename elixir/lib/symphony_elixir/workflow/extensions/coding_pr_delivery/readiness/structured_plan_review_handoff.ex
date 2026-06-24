defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff do
  @moduledoc """
  Optional structured execution plan checks for coding PR review handoff.

  These checks are disabled by default. When enabled, they consume structured
  plans through a plugin-owned reader port and structured readiness
  observations; rendered Workpad text is never parsed as authority.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.Options

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.StructuredPlanReviewHandoff.{
    CategoryChecks,
    Check,
    Context,
    ObservedEvidence,
    Plan.Reader,
    Plan.Scope
  }

  @plan_check_key "structured_execution_plan"
  @gate_misconfigured_reason "structured_plan_gate_misconfigured"
  @options_invalid_reason "structured_plan_options_invalid"
  @store_unavailable_code "store_unavailable"
  @store_unavailable_reason "structured_plan_store_unavailable"
  @plan_missing_reason "structured_plan_missing"

  @options_invalid_detail "Structured plan review-handoff options must be a keyword list."
  @gate_misconfigured_detail "Structured plan review handoff requires structured execution plans to be enabled."
  @store_unavailable_detail "Canonical structured execution plan store is unavailable."
  @plan_missing_detail "A canonical structured execution plan is required."

  @spec checks(map() | struct() | nil, map(), map(), keyword()) :: [map()]
  def checks(workflow, issue, observations, opts) when is_map(issue) and is_map(observations) do
    case Options.normalize(opts) do
      {:ok, opts} ->
        opts
        |> Context.gate_state()
        |> checks_for_gate(workflow, issue, observations, opts)

      {:error, reason} ->
        [
          Check.failed(
            @plan_check_key,
            @options_invalid_reason,
            @options_invalid_detail,
            ObservedEvidence.options_error(reason)
          )
        ]
    end
  end

  def checks(_workflow, _issue, _observations, _opts), do: []

  defp checks_for_gate(:disabled, _workflow, _issue, _observations, _opts), do: []

  defp checks_for_gate({:misconfigured, _reason}, _workflow, _issue, _observations, _opts) do
    [Check.failed(@plan_check_key, @gate_misconfigured_reason, @gate_misconfigured_detail, [])]
  end

  defp checks_for_gate(:enabled, workflow, issue, observations, opts) do
    config = Context.structured_plan_opts(opts)
    context = Context.build(workflow, issue, opts, config)

    case Reader.fetch(context, config, opts) do
      {:ok, plan} ->
        case Scope.check(plan, context, observations) do
          {:ok, plan_check} -> [plan_check | CategoryChecks.checks(plan)]
          {:error, plan_check} -> [plan_check]
        end

      {:error, %{code: @store_unavailable_code} = reason} ->
        [Check.failed(@plan_check_key, @store_unavailable_reason, @store_unavailable_detail, ObservedEvidence.error(reason))]

      {:error, reason} ->
        [Check.missing(@plan_check_key, @plan_missing_reason, @plan_missing_detail, ObservedEvidence.error(reason))]
    end
  end
end
