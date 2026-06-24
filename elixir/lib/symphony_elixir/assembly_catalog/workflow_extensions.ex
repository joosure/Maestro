defmodule SymphonyElixir.AssemblyCatalog.WorkflowExtensions do
  @moduledoc """
  Application-assembly source for bundled workflow runtime extensions.

  This module may name concrete built-in extension modules because it is part of
  deployment composition, not the Workflow platform core. The runtime registry
  still depends only on the source behaviour.

  External workflow plugins must be independently released OTP applications.
  They must register through their own source or a future manifest projection;
  do not add externally owned plugin modules to this bundled-extension catalog
  or to `SymphonyElixir.Workflow.Extensions`.
  """

  @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

  @impl true
  def extension_modules(_opts) do
    [
      SymphonyElixir.Workflow.Extensions.CodingPrDelivery
    ]
  end
end
