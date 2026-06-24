defmodule SymphonyElixir.Workflow.Extension.Registry.Source do
  @moduledoc """
  Source behaviour for workflow runtime-extension registration.

  A source is an application-assembly boundary: it returns trusted workflow
  extension modules without making runtime registries or root config files name
  concrete workflow business modules directly.
  """

  @callback extension_modules(keyword()) :: [module()]
end
