defmodule SymphonyElixir.AssemblyCatalog.DynamicToolSources do
  @moduledoc """
  Application-assembly catalog for bundled Dynamic Tool source modules.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.SourceCatalog

  @impl true
  def source_specs(_opts) do
    [
      SymphonyElixir.Tracker.DynamicToolSource,
      SymphonyElixir.Repo.DynamicToolSource,
      SymphonyElixir.RepoProvider.DynamicToolSource
    ]
  end
end
