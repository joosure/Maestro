defmodule SymphonyElixir.Orchestrator.Dispatch do
  @moduledoc false

  alias SymphonyElixir.Issue

  alias SymphonyElixir.Orchestrator.Dispatch.{
    Context,
    Eligibility,
    Ordering,
    Revalidation,
    RoutePreparation
  }

  @type context :: %{
          active_state_names: [String.t()],
          terminal_state_names: [String.t()],
          state_phase_map: map(),
          max_concurrent_agents_for_state: (term() -> pos_integer()) | nil
        }

  @type runtime :: %{
          optional(:running) => map(),
          optional(:claimed) => [term()],
          optional(:orchestrator_slots) => integer(),
          optional(:worker_slots_available?) => boolean()
        }

  @spec new_context(term(), term(), keyword()) :: context()
  def new_context(active_states, terminal_states, opts \\ []) do
    Context.new(active_states, terminal_states, opts)
  end

  @spec sort_issues_for_dispatch(list()) :: list()
  def sort_issues_for_dispatch(issues) when is_list(issues), do: Ordering.sort(issues)

  @spec should_dispatch_issue?(Issue.t(), runtime(), context()) :: boolean()
  def should_dispatch_issue?(issue, runtime, context), do: Eligibility.should_dispatch_issue?(issue, runtime, context)

  @spec dispatch_skip_reason(Issue.t(), runtime(), context()) :: atom() | nil
  def dispatch_skip_reason(issue, runtime, context), do: Eligibility.dispatch_skip_reason(issue, runtime, context)

  @spec issue_routable_to_worker?(Issue.t()) :: boolean()
  def issue_routable_to_worker?(issue), do: Eligibility.issue_routable_to_worker?(issue)

  @spec terminal_issue_state?(Issue.t(), term(), context()) :: boolean()
  def terminal_issue_state?(issue, state_name, context), do: Eligibility.terminal_issue_state?(issue, state_name, context)

  @spec active_issue_state?(Issue.t(), term(), context()) :: boolean()
  def active_issue_state?(issue, state_name, context), do: Eligibility.active_issue_state?(issue, state_name, context)

  @spec retry_candidate_issue?(Issue.t(), context()) :: boolean()
  def retry_candidate_issue?(issue, context), do: Eligibility.retry_candidate_issue?(issue, context)

  @spec dispatch_slots_available?(Issue.t(), runtime(), context()) :: boolean()
  def dispatch_slots_available?(issue, runtime, context), do: Eligibility.dispatch_slots_available?(issue, runtime, context)

  @spec revalidate_issue_for_dispatch(Issue.t(), ([String.t()] -> term()), context()) ::
          {:ok, Issue.t()} | {:skip, Issue.t() | :missing} | {:error, term()}
  def revalidate_issue_for_dispatch(issue, issue_fetcher, context) do
    Revalidation.revalidate(issue, issue_fetcher, context)
  end

  @spec prepare_issue_for_dispatch(
          Issue.t(),
          ([String.t()] -> term()),
          (String.t(), term() -> term()),
          context(),
          keyword()
        ) :: {:ok, Issue.t()} | {:skip, Issue.t() | :missing} | {:error, term()}
  def prepare_issue_for_dispatch(issue, issue_fetcher, state_updater, context, opts \\ []) do
    RoutePreparation.prepare(issue, issue_fetcher, state_updater, context, opts)
  end
end
