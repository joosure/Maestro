defmodule SymphonyElixir.Orchestrator.Dispatch.Ordering do
  @moduledoc false

  alias SymphonyElixir.Issue

  @max_sort_timestamp 9_223_372_036_854_775_807

  @spec sort(list()) :: list()
  def sort(issues) when is_list(issues) do
    Enum.sort_by(issues, fn
      %Issue{} = issue ->
        {priority_rank(issue.priority), issue_created_at_sort_key(issue), issue.identifier || issue.id || ""}

      _other ->
        {priority_rank(nil), issue_created_at_sort_key(nil), ""}
    end)
  end

  defp priority_rank(priority) when is_integer(priority) and priority in 1..4, do: priority
  defp priority_rank(_priority), do: 5

  defp issue_created_at_sort_key(%Issue{created_at: %DateTime{} = created_at}) do
    DateTime.to_unix(created_at, :microsecond)
  end

  defp issue_created_at_sort_key(%Issue{}), do: @max_sort_timestamp
  defp issue_created_at_sort_key(_issue), do: @max_sort_timestamp
end
