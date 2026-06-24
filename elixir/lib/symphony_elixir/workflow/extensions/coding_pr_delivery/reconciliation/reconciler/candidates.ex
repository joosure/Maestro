defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Candidates do
  @moduledoc false

  alias SymphonyElixir.Issue
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Clients
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.EventEmitter
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.TargetReference
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Runtime.Input, as: RuntimeInput
  alias SymphonyElixir.Workflow.RouteRef

  @targeted_issue_ids_limit 100

  @spec targeted_issue_ids(Options.t(), pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def targeted_issue_ids(%Options{} = options, limit) when is_integer(limit) do
    limit = min(limit, @targeted_issue_ids_limit)

    case Clients.targeted_issue_ids(limit, options) do
      {:ok, values} -> {:ok, normalize_targeted_issue_ids(values, limit)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch([String.t()], [String.t()], Config.t(), Options.t()) ::
          {:ok, atom(), [Issue.t()]} | {:error, term()}
  def fetch(_source_raw_states, [], %Config{candidate_discovery: :runtime_targeted}, %Options{}) do
    {:ok, :runtime_targeted_empty, []}
  end

  def fetch(source_raw_states, [], %Config{}, %Options{} = options) do
    case Clients.fetch_issues_by_states(source_raw_states, options) do
      {:ok, issues} -> {:ok, :source_route_scan, issues}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(_source_raw_states, targeted_issue_ids, %Config{}, %Options{} = options)
      when is_list(targeted_issue_ids) do
    case Clients.fetch_issue_states_by_ids(targeted_issue_ids, options) do
      {:ok, issues} -> {:ok, :targeted_issue_ids, issues}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reject_running([term()], RuntimeInput.t(), atom(), Options.t()) :: [Issue.t()]
  def reject_running(issues, %RuntimeInput{} = runtime, fetch_mode, %Options{} = options) when is_list(issues) do
    {deferred_issue_ids, candidate_issues} =
      Enum.reduce(issues, {[], []}, fn
        %Issue{id: issue_id} = issue, {deferred, candidates} when is_binary(issue_id) ->
          if RuntimeInput.running_issue?(runtime, issue_id) or RuntimeInput.claimed_issue?(runtime, issue_id) do
            {[issue_id | deferred], candidates}
          else
            {deferred, [issue | candidates]}
          end

        _issue, acc ->
          acc
      end)

    defer_targeted_issue_ids(Enum.reverse(deferred_issue_ids), fetch_mode, options, %{
      reason: :running_or_claimed
    })

    Enum.reverse(candidate_issues)
  end

  def reject_running(_issues, _runtime, _fetch_mode, %Options{}), do: []

  @spec maybe_defer_known_target(Issue.t(), map(), map(), atom(), Options.t()) :: :ok
  def maybe_defer_known_target(%Issue{id: issue_id} = issue, context, route_facts, :targeted_issue_ids, %Options{} = options)
      when is_binary(issue_id) and is_map(context) and is_map(route_facts) do
    if route_facts.action != :stop and not is_nil(TargetReference.known_target_reference(issue, options)) do
      defer_targeted_issue_ids([issue_id], :targeted_issue_ids, options, %{
        reason: :source_route_pending,
        route_ref: RouteRef.new!(context.profile_context, route_facts.route_key)
      })
    else
      :ok
    end
  end

  def maybe_defer_known_target(_issue, _context, _route_facts, _fetch_mode, %Options{}), do: :ok

  defp defer_targeted_issue_ids([], _fetch_mode, _options, _details), do: :ok

  defp defer_targeted_issue_ids(issue_ids, :targeted_issue_ids, %Options{} = options, details)
       when is_list(issue_ids) and is_map(details) do
    details_opts = defer_details_opts(details)

    issue_ids
    |> Clients.defer_targeted_issue_ids(details_opts, options)
    |> EventEmitter.candidate_suspended(issue_ids, details, options)

    :ok
  end

  defp defer_targeted_issue_ids(_issue_ids, _fetch_mode, _options, _details), do: :ok

  defp defer_details_opts(details) when is_map(details) do
    details
    |> Enum.flat_map(fn
      {:reason, reason} -> [reason: reason]
      {:route, route} -> [route: route]
      {:route_ref, %RouteRef{route_key: route_key}} -> [route: route_key]
      _detail -> []
    end)
  end

  defp normalize_targeted_issue_ids({:ok, values}, limit), do: normalize_targeted_issue_ids(values, limit)
  defp normalize_targeted_issue_ids(result, _limit) when not is_list(result), do: []

  defp normalize_targeted_issue_ids(values, limit) when is_list(values) do
    limit = max(limit, 0)

    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> []
          trimmed -> [trimmed]
        end

      _value ->
        []
    end)
    |> Enum.uniq()
    |> Enum.take(limit)
  end
end
