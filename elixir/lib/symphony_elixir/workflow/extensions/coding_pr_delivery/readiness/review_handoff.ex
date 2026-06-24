defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff do
  @moduledoc """
  Review-handoff readiness policy facade for Coding PR Delivery.

  This module is the stable policy contribution exported to the platform
  readiness registry. Internal target resolution, evidence loading, checks, and
  result construction live in `ReviewHandoff.Validator` so the exported policy
  boundary stays thin enough for an external plugin package.
  """

  @behaviour SymphonyElixir.Workflow.StateTransitionReadiness.Policy

  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Validator

  @type validation_result :: Validator.validation_result()

  @impl true
  @spec policy_id() :: String.t()
  defdelegate policy_id, to: Validator

  @impl true
  @spec schema() :: String.t()
  defdelegate schema, to: Validator

  @impl true
  @spec governed_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  defdelegate governed_target?(workflow, target_state_name), to: Validator

  @spec review_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  defdelegate review_target?(workflow, target_state_name), to: Validator

  @impl true
  @spec validate(Effective.t() | map() | nil, map(), keyword()) :: validation_result()
  defdelegate validate(workflow, issue, opts \\ []), to: Validator

  @spec validate_evidence(Effective.t() | map() | nil, map(), map(), keyword()) :: map()
  defdelegate validate_evidence(workflow, issue, evidence, opts \\ []), to: Validator
end
