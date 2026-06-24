defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.RuntimeDefaults do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox

  @spec reconciler_opts(keyword()) :: keyword()
  def reconciler_opts(opts) when is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "Coding PR Delivery runtime defaults options must be a keyword list."
    end

    [
      targeted_issue_ids_fn: fn limit -> Inbox.drain_issue_ids(limit: limit) end,
      defer_targeted_issue_ids_fn: &Inbox.defer_issue_ids/2
    ]
    |> Keyword.merge(opts)
  end

  def reconciler_opts(opts) do
    raise ArgumentError,
          "Coding PR Delivery runtime defaults options must be a keyword list. value_type=#{Diagnostics.type_name(opts)}"
  end
end
