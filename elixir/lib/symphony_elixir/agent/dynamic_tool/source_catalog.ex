defmodule SymphonyElixir.Agent.DynamicTool.SourceCatalog do
  @moduledoc """
  Behaviour for application-assembly modules that list Dynamic Tool source specs.

  `Agent.DynamicTool.Source.Config` owns catalog expansion and source
  validation. Catalog modules sit at the application assembly boundary: they may
  name trusted built-in source modules, but they must not implement Dynamic Tool
  execution or provider-specific business rules.
  """

  @callback source_specs(keyword()) :: [module() | {module(), term()}]
end
