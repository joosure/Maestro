defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog do
  @moduledoc """
  Template entries contributed by the built-in Coding PR Delivery extension.

  This module depends on the public `Workflow.Template` facade, not registry
  internals, so the same shape can later be sourced from an external plugin
  manifest.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.TemplateCatalog.{Assets, Contract, CredentialPolicy}
  alias SymphonyElixir.Workflow.Template

  @spec entries(keyword()) :: [Template.entry()]
  def entries(opts \\ []) do
    asset_root = Assets.root!(opts)

    Contract.entries()
    |> Enum.map(&template(&1, asset_root, opts))
  end

  defp template(entry, asset_root, opts) when is_map(entry) do
    Template.entry!(
      template_alias: Map.fetch!(entry, :template_alias),
      asset_root: asset_root,
      profile_kind: Profile.kind(),
      profile_version: Profile.version(),
      tracker_kind: Map.fetch!(entry, :tracker_kind),
      repo_provider_kind: Map.fetch!(entry, :repo_provider_kind),
      agent_provider_kind: Map.fetch!(entry, :agent_provider_kind),
      credential_ref: CredentialPolicy.credential_ref(entry, opts)
    )
  end
end
