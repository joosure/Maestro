defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation do
  @moduledoc """
  Remediation actions for failed Coding PR Delivery review-handoff checks.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.Capabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.CapabilityProvider
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Result

  @default_capability_provider Capabilities
  @reason_code_key Result.reason_code_key()
  @remediation_check_key Contract.remediation_check_key()
  @remediation_action_key Contract.remediation_action_key()
  @remediation_capabilities_key Contract.remediation_capabilities_key()

  @spec actions([map()], keyword()) :: [map()]
  def actions(checks, opts \\ [])

  def actions(checks, opts) when is_list(checks) do
    capability_provider = capability_provider(opts)

    checks
    |> Enum.map(&action(&1, capability_provider))
    |> Enum.uniq()
  end

  def actions(_checks, _opts), do: []

  defp action(check, capability_provider) when is_map(check) do
    reason_code = Map.fetch!(check, @reason_code_key)
    check_key = Map.fetch!(check, ReadinessContract.key_key())
    {message, capability_ref} = action_for_check(check_key)

    %{
      @reason_code_key => reason_code,
      @remediation_check_key => check_key,
      @remediation_action_key => message,
      @remediation_capabilities_key => capabilities(capability_provider, capability_ref)
    }
  end

  defp action_for_check(check_key) do
    cond do
      check_key == Contract.check_key(:issue_snapshot) ->
        {"Refresh the structured tracker issue snapshot before retrying the review handoff.", :issue_snapshot}

      check_key == Contract.check_key(:workpad_recorded) ->
        {"Write the final handoff record after the latest repository, PR, checks, and feedback evidence.", :workpad_recorded}

      check_key == Contract.check_key(:implementation_evidence) ->
        {"Record repository implementation evidence from the repo typed tools before review handoff.", :implementation_evidence}

      check_key == Contract.check_key(:validation_passed) ->
        {"Record passing validation evidence for the latest pushed head before review handoff.", :validation_passed}

      check_key == Contract.check_key(:change_proposal_linked) ->
        {"Create or refresh the change proposal and attach/link it to the tracker issue.", :change_proposal_linked}

      check_key == Contract.check_key(:change_proposal_checks) ->
        {"Read change-proposal checks for the latest change proposal head and wait until they pass or are not required.", :change_proposal_checks}

      check_key == Contract.check_key(:feedback_clear) ->
        {"Read provider discussion/review feedback and resolve or explicitly clear all actionable feedback.", :feedback_clear}

      true ->
        {"Refresh the missing structured evidence and retry the review handoff.", :unknown}
    end
  end

  defp capability_provider(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :capability_provider, @default_capability_provider) do
        provider when is_atom(provider) and not is_nil(provider) ->
          if CapabilityProvider.valid?(provider), do: provider, else: @default_capability_provider

        _provider ->
          @default_capability_provider
      end
    else
      @default_capability_provider
    end
  end

  defp capability_provider(_opts), do: @default_capability_provider

  defp capabilities(provider, capability_ref) when is_atom(provider) and is_atom(capability_ref) do
    if CapabilityProvider.valid?(provider) and function_exported?(provider, capability_ref, 0) do
      provider
      |> apply(capability_ref, [])
      |> normalize_capabilities()
    else
      []
    end
  end

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    Enum.filter(capabilities, &is_binary/1)
  end

  defp normalize_capabilities(_capabilities), do: []
end
