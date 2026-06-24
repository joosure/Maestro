defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.CapabilityProvider do
  @moduledoc """
  Capability-provider contract for Coding PR Delivery review-handoff remediation.

  Remediation rules depend on this extension-owned contract instead of concrete
  Tracker/Repo/RepoProvider capability modules. Bundled deployments use
  `Remediation.Capabilities`; an external plugin package can replace that
  provider without changing rule code.
  """

  @callback issue_snapshot() :: [String.t()]
  @callback workpad_recorded() :: [String.t()]
  @callback implementation_evidence() :: [String.t()]
  @callback validation_passed() :: [String.t()]
  @callback change_proposal_linked() :: [String.t()]
  @callback change_proposal_checks() :: [String.t()]
  @callback feedback_clear() :: [String.t()]
  @callback unknown() :: [String.t()]

  @required_callbacks [
    :issue_snapshot,
    :workpad_recorded,
    :implementation_evidence,
    :validation_passed,
    :change_proposal_linked,
    :change_proposal_checks,
    :feedback_clear,
    :unknown
  ]

  @spec valid?(module()) :: boolean()
  def valid?(provider) when is_atom(provider) and not is_nil(provider) do
    Code.ensure_loaded?(provider) and
      Enum.all?(@required_callbacks, &function_exported?(provider, &1, 0))
  end

  def valid?(_provider), do: false
end
