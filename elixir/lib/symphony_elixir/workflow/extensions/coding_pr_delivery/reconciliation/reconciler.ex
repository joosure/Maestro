defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.{
    Candidates,
    Diagnostics,
    IssueRunner,
    Options
  }

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.{Config, Contract, Events, RouteContext}
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput

  @type result :: %{
          extension_state: map(),
          commands: list()
        }

  @spec reconcile(map(), RuntimeInput.t(), keyword()) :: result()
  def reconcile(settings, %RuntimeInput{} = runtime, opts \\ []) when is_map(settings) do
    case Options.normalize(opts) do
      {:ok, %Options{} = options} ->
        reconcile_with_options(settings, runtime, options)

      {:error, reason} ->
        complete_with_error(settings, runtime, System.monotonic_time(:millisecond), reason, 0)
    end
  end

  defp reconcile_with_options(settings, runtime, %Options{} = options) do
    case Config.from_settings(settings) do
      {:ok, %Config{enabled?: false}} ->
        result(runtime.extension_state)

      {:ok, %Config{} = config} ->
        do_reconcile(settings, config, runtime, options)

      {:error, reason} ->
        Events.config_invalid(settings, runtime, reason)
        result(runtime.extension_state)
    end
  end

  defp do_reconcile(settings, config, runtime, %Options{} = options) do
    started_at_ms = System.monotonic_time(:millisecond)
    source_raw_states = RouteContext.source_raw_states(settings, config)

    case Candidates.targeted_issue_ids(options, config.max_processed_candidate_issues_per_cycle) do
      {:ok, targeted_issue_ids} ->
        reconcile_candidates(settings, config, runtime, options, source_raw_states, targeted_issue_ids, started_at_ms)

      {:error, reason} ->
        complete_with_error(settings, runtime, started_at_ms, reason, 0)
    end
  end

  defp reconcile_candidates(settings, config, runtime, options, source_raw_states, targeted_issue_ids, started_at_ms) do
    Events.reconciliation_started(settings, runtime, config, source_raw_states)

    case Candidates.fetch(source_raw_states, targeted_issue_ids, config, options) do
      {:ok, fetch_mode, issues} ->
        candidate_issues = Candidates.reject_running(issues, runtime, fetch_mode, options)

        {updated_extension_state, processed_count} =
          candidate_issues
          |> Enum.take(config.max_processed_candidate_issues_per_cycle)
          |> Enum.reduce({runtime.extension_state, 0}, fn issue, {state_acc, count} ->
            {
              IssueRunner.run(settings, config, issue, runtime, state_acc, fetch_mode, options),
              count + 1
            }
          end)

        Events.reconciliation_completed(settings, runtime, :info, %{
          status: Contract.reconciliation_status(:ok),
          candidate_fetch_mode: fetch_mode,
          targeted_issue_count: length(targeted_issue_ids),
          source_state_count: length(source_raw_states),
          candidate_count: length(issues),
          processed_count: processed_count,
          duration_ms: elapsed_ms(started_at_ms)
        })

        result(updated_extension_state)

      {:error, reason} ->
        complete_with_error(settings, runtime, started_at_ms, reason, length(targeted_issue_ids))
    end
  end

  defp complete_with_error(settings, runtime, started_at_ms, reason, targeted_issue_count) do
    Events.reconciliation_completed(settings, runtime, :warning, %{
      status: Contract.reconciliation_status(:tracker_error),
      error: Diagnostics.error_string(reason),
      targeted_issue_count: targeted_issue_count,
      duration_ms: elapsed_ms(started_at_ms)
    })

    result(runtime.extension_state)
  end

  defp elapsed_ms(started_at_ms) when is_integer(started_at_ms) do
    System.monotonic_time(:millisecond) - started_at_ms
  end

  defp result(extension_state) when is_map(extension_state) do
    %{extension_state: extension_state, commands: []}
  end
end
