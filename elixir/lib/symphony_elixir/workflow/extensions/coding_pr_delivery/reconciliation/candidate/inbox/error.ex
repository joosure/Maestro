defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics

  @invalid_options_code "invalid_coding_pr_delivery_candidate_inbox_options"
  @invalid_issue_ids_code "invalid_coding_pr_delivery_candidate_inbox_issue_ids"
  @invalid_server_code "invalid_coding_pr_delivery_candidate_inbox_server"
  @unavailable_code "coding_pr_delivery_candidate_inbox_unavailable"

  @spec invalid_options(atom(), term()) :: map()
  def invalid_options(reason, value) when is_atom(reason) do
    %{
      code: @invalid_options_code,
      reason: reason,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_issue_ids(term()) :: map()
  def invalid_issue_ids(value) do
    %{
      code: @invalid_issue_ids_code,
      reason: :issue_ids_not_list,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec invalid_server(term()) :: map()
  def invalid_server(value) do
    %{
      code: @invalid_server_code,
      reason: :server_not_pid_or_atom,
      value_type: Diagnostics.type_name(value)
    }
  end

  @spec unavailable(term()) :: map()
  def unavailable(server) do
    %{
      code: @unavailable_code,
      reason: :candidate_inbox_unavailable,
      server_type: Diagnostics.type_name(server)
    }
  end
end
