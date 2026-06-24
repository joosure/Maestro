defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation do
  @moduledoc """
  Coordinates tracker issue state with repository change-proposal readiness.

  This context owns the cross-boundary use case:

    * discover the issue's attached change proposal through the tracker facade
    * inspect provider-specific review/check/mergeability state through the repo-provider facade
    * apply workflow policy to decide whether the tracker issue should move routes
    * delegate route resolution, transition confirmation, counters, and events
      to focused modules under this context

  Orchestrator code should call this facade as a poll-cycle capability instead of
  binding directly to tracker or repo-provider reconciliation details.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Candidate.Inbox
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput

  @spec reconcile_runtime(map(), RuntimeInput.t(), keyword()) :: Reconciler.result()
  defdelegate reconcile_runtime(settings, runtime_input, opts \\ []), to: Reconciler, as: :reconcile

  @spec enqueue_issue_ids([term()], keyword()) ::
          {:ok, Inbox.enqueue_result()} | {:error, term()}
  defdelegate enqueue_issue_ids(issue_ids, opts \\ []), to: Inbox

  @spec register_known_target(map(), keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate register_known_target(attrs, opts \\ []), to: Registration, as: :register

  @spec known_targets(keyword()) :: [Registration.target()] | {:error, term()}
  defdelegate known_targets(opts \\ []), to: Registration, as: :targets

  @spec run_known_target_watcher_once(keyword()) :: Producer.Watcher.run_result()
  defdelegate run_known_target_watcher_once(opts \\ []), to: Producer.Watcher, as: :run_once
end
