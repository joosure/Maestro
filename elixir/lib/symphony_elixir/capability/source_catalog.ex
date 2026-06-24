defmodule SymphonyElixir.Capability.SourceCatalog do
  @moduledoc """
  Behaviour for application-assembly modules that list capability sources.

  The platform capability registry owns aggregation mechanics. Domain contexts
  own concrete capability strings. Catalog modules sit between those layers and
  name trusted built-in source modules without moving that list into the
  registry mechanism itself.
  """

  @callback source_modules() :: [module()]
end
