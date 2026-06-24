defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator do
  @moduledoc """
  Validates machine-readable completion evidence for Coding PR Delivery.

  This module is the registered extension facade. Evidence reading, predicate
  checks, observed labels, option validation, and result envelopes live in
  focused completion-validator submodules.
  """

  @behaviour SymphonyElixir.Workflow.Extension.CompletionValidator

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.CheckSet
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.EvidenceReader
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.CompletionValidator.ResultBuilder
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery

  @type validation_result :: %{required(String.t()) => term()}

  @impl true
  def profile_kind, do: CodingPrDelivery.kind()

  @impl true
  @spec validate(map(), keyword()) :: validation_result()
  def validate(issue, opts \\ [])

  def validate(issue, opts) when is_map(issue) do
    with {:ok, opts} <- Options.normalize(opts),
         {:ok, context} <- EvidenceReader.context(issue, opts) do
      %{
        profile_context: profile_context,
        evidence: evidence,
        allowed_routes: allowed_routes,
        route_key: route_key
      } = context

      if profile_context.kind == profile_kind() do
        evidence
        |> CheckSet.validation_checks(route_key, allowed_routes)
        |> then(&ResultBuilder.validation_result(profile_context, route_key, allowed_routes, &1))
      else
        ResultBuilder.skipped(profile_context, route_key, allowed_routes)
      end
    else
      {:error, %{code: :invalid_completion_validator_options} = reason} ->
        ResultBuilder.invalid_options(reason)

      {:error, reason} ->
        ResultBuilder.invalid_input(reason)
    end
  end

  def validate(issue, _opts), do: issue |> Options.invalid_issue() |> ResultBuilder.invalid_input()

  @impl true
  @spec merge_gate(map(), map()) :: validation_result()
  def merge_gate(evidence, capabilities \\ %{})

  def merge_gate(evidence, capabilities) when is_map(evidence) and is_map(capabilities) do
    evidence
    |> CheckSet.merge_gate_checks(capabilities)
    |> ResultBuilder.merge_gate_result()
  end

  def merge_gate(evidence, _capabilities) when not is_map(evidence),
    do: evidence |> Options.invalid_evidence() |> ResultBuilder.invalid_input()

  def merge_gate(_evidence, capabilities),
    do: capabilities |> Options.invalid_capabilities() |> ResultBuilder.invalid_input()
end
