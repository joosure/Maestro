defmodule SymphonyElixir.AssemblyCatalog.StorageContracts do
  @moduledoc """
  Application-assembly source for bundled platform storage contracts.

  This module may name concrete built-in domain storage contracts because it is
  a deployment-composition boundary, not the storage infrastructure context.
  Keep storage mechanics and table-catalog behaviour in `SymphonyElixir.Storage`.
  """

  @behaviour SymphonyElixir.Storage.TableCatalog.Source

  @impl true
  def entry_modules(_opts) do
    [
      SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract,
      SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract,
      SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract
    ]
  end
end
