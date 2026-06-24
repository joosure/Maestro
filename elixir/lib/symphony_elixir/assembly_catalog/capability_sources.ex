defmodule SymphonyElixir.AssemblyCatalog.CapabilitySources do
  @moduledoc """
  Application-assembly catalog for bundled capability source modules.

  This module may name built-in domain capability sources because it is a
  deployment-composition boundary, not the platform capability registry. Keep
  capability strings in the owning domain modules.
  """

  @behaviour SymphonyElixir.Capability.SourceCatalog

  @impl true
  def source_modules do
    [
      SymphonyElixir.Tracker.Capabilities,
      SymphonyElixir.Repo.Capabilities,
      SymphonyElixir.RepoProvider.Capabilities,
      SymphonyElixir.Agent.Capabilities,
      SymphonyElixir.Workflow.CapabilityNames
    ]
  end
end
