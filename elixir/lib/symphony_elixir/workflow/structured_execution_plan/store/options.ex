defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Options do
  @moduledoc """
  Store option boundary for workflow structured execution-plan callers.

  Public orchestration modules should not know which storage/backend options the
  Store accepts. They pass their caller opts through this module instead.
  """

  @initializer_opts [
    :server,
    :updated_at,
    :agent_store,
    :agent_store_mode,
    :workflow_storage_backend,
    :workflow_storage_opts,
    :backend,
    :repo,
    :max_records
  ]

  @spec from_adoption_initializer(keyword()) :: keyword()
  def from_adoption_initializer(opts) when is_list(opts), do: Keyword.take(opts, @initializer_opts)
end
