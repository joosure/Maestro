defmodule SymphonyElixir.Orchestrator.Dispatch.Revalidation do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Orchestrator.Dispatch.{Context, Eligibility}

  @spec revalidate(Issue.t(), ([String.t()] -> term()), Context.t()) ::
          {:ok, Issue.t()} | {:skip, Issue.t() | :missing} | {:error, term()}
  def revalidate(%Issue{id: issue_id}, issue_fetcher, context)
      when is_binary(issue_id) and is_function(issue_fetcher, 1) and is_map(context) do
    case issue_fetcher.([issue_id]) do
      {:ok, [%Issue{} = refreshed_issue | _]} ->
        if Eligibility.retry_candidate_issue?(refreshed_issue, context) do
          {:ok, refreshed_issue}
        else
          {:skip, refreshed_issue}
        end

      {:ok, []} ->
        {:skip, :missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revalidate(issue, _issue_fetcher, _context), do: {:ok, issue}
end
