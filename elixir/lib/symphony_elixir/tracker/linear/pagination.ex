defmodule SymphonyElixir.Tracker.Linear.Pagination do
  @moduledoc false

  alias SymphonyElixir.Issue

  @spec next_page_cursor(map()) :: {:ok, String.t()} | :done | {:error, term()}
  def next_page_cursor(%{has_next_page: true, end_cursor: end_cursor})
      when is_binary(end_cursor) and byte_size(end_cursor) > 0 do
    {:ok, end_cursor}
  end

  def next_page_cursor(%{has_next_page: true}), do: {:error, :linear_missing_end_cursor}
  def next_page_cursor(_page_info), do: :done

  @spec prepend_page_issues([Issue.t()], [Issue.t()]) :: [Issue.t()]
  def prepend_page_issues(issues, acc_issues) when is_list(issues) and is_list(acc_issues) do
    Enum.reverse(issues, acc_issues)
  end

  @spec finalize_paginated_issues([Issue.t()]) :: [Issue.t()]
  def finalize_paginated_issues(acc_issues) when is_list(acc_issues), do: Enum.reverse(acc_issues)

  @spec issue_order_index([String.t()]) :: map()
  def issue_order_index(ids) when is_list(ids) do
    ids
    |> Enum.with_index()
    |> Map.new()
  end

  @spec sort_issues_by_requested_ids([Issue.t()], map()) :: [Issue.t()]
  def sort_issues_by_requested_ids(issues, issue_order_index)
      when is_list(issues) and is_map(issue_order_index) do
    unknown_index = map_size(issue_order_index)

    Enum.sort_by(issues, fn
      %Issue{id: issue_id} -> Map.get(issue_order_index, issue_id, unknown_index)
      _other -> unknown_index
    end)
  end
end
