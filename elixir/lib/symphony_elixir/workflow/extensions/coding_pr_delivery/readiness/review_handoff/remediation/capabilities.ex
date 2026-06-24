defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.Capabilities do
  @moduledoc """
  Bundled capability provider for Coding PR Delivery review-handoff remediation.

  `ReviewHandoff.Remediation` owns remediation semantics. This module adapts
  those semantics to the built-in platform capability strings. An external
  plugin package can provide a replacement capability provider without changing
  the remediation rule module.
  """

  alias SymphonyElixir.Repo.Capabilities, as: RepoCapabilities
  alias SymphonyElixir.RepoProvider.Capabilities, as: RepoProviderCapabilities
  alias SymphonyElixir.Tracker.Capabilities, as: TrackerCapabilities
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Remediation.CapabilityProvider

  @behaviour CapabilityProvider

  @spec issue_snapshot() :: [String.t()]
  @impl CapabilityProvider
  def issue_snapshot, do: [TrackerCapabilities.issue_snapshot()]

  @spec workpad_recorded() :: [String.t()]
  @impl CapabilityProvider
  def workpad_recorded, do: [TrackerCapabilities.upsert_workpad()]

  @spec implementation_evidence() :: [String.t()]
  @impl CapabilityProvider
  def implementation_evidence, do: [RepoCapabilities.commit(), RepoCapabilities.push()]

  @spec validation_passed() :: [String.t()]
  @impl CapabilityProvider
  def validation_passed, do: [RepoCapabilities.diff()]

  @spec change_proposal_linked() :: [String.t()]
  @impl CapabilityProvider
  def change_proposal_linked do
    [
      RepoProviderCapabilities.create_or_update_change_proposal(),
      TrackerCapabilities.attach_external_reference()
    ]
  end

  @spec change_proposal_checks() :: [String.t()]
  @impl CapabilityProvider
  def change_proposal_checks, do: [RepoProviderCapabilities.read_change_proposal_checks()]

  @spec feedback_clear() :: [String.t()]
  @impl CapabilityProvider
  def feedback_clear, do: [RepoProviderCapabilities.read_change_proposal_discussion()]

  @spec unknown() :: [String.t()]
  @impl CapabilityProvider
  def unknown, do: []
end
