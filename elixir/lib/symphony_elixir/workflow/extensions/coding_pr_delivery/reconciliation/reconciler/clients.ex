defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Clients do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Reconciler.Options
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.TrackerCallOptions

  @spec fetch_issues_by_states([String.t()], Options.t()) :: {:ok, list()} | {:error, term()}
  def fetch_issues_by_states(states, %Options{} = options) when is_list(states) do
    options.fetch_issues_by_states_fn
    |> safe_call(:fetch_issues_by_states, [states, TrackerCallOptions.fetch(options.raw_opts)])
    |> normalize_tagged_result(:fetch_issues_by_states)
  end

  @spec fetch_issue_states_by_ids([String.t()], Options.t()) :: {:ok, list()} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, %Options{} = options) when is_list(issue_ids) do
    options.fetch_issue_states_by_ids_fn
    |> safe_call(:fetch_issue_states_by_ids, [issue_ids, TrackerCallOptions.fetch(options.raw_opts)])
    |> normalize_tagged_result(:fetch_issue_states_by_ids)
  end

  @spec targeted_issue_ids(pos_integer(), Options.t()) :: {:ok, term()} | {:error, term()}
  def targeted_issue_ids(_limit, %Options{targeted_issue_ids: targeted_issue_ids}) when targeted_issue_ids != :unset do
    {:ok, targeted_issue_ids}
  end

  def targeted_issue_ids(limit, %Options{targeted_issue_ids_fn: nil}) when is_integer(limit), do: {:ok, []}

  def targeted_issue_ids(limit, %Options{} = options) when is_integer(limit) do
    args =
      if is_function(options.targeted_issue_ids_fn, 1) do
        [limit]
      else
        []
      end

    options.targeted_issue_ids_fn
    |> safe_call(:targeted_issue_ids, args)
    |> normalize_optional_ok_result(:targeted_issue_ids)
  end

  @spec custom_change_proposal_reference(term(), Options.t()) :: :default | {:ok, term()} | {:error, term()}
  def custom_change_proposal_reference(_issue, %Options{change_proposal_reference_fn: nil}), do: :default

  def custom_change_proposal_reference(issue, %Options{} = options) do
    options.change_proposal_reference_fn
    |> safe_call(:change_proposal_reference, [issue, options.raw_opts])
    |> normalize_optional_ok_result(:change_proposal_reference)
  end

  @spec change_proposal_facts(map(), term(), Options.t()) :: {:ok, term()} | {:error, term()}
  def change_proposal_facts(repo_config, target, %Options{} = options) when is_map(repo_config) do
    options.change_proposal_facts_fn
    |> safe_call(:change_proposal_facts, [repo_config, target, options.raw_opts])
    |> normalize_optional_ok_result(:change_proposal_facts)
  end

  @spec defer_targeted_issue_ids([String.t()], keyword(), Options.t()) :: :ok | {:ok, term()} | {:error, term()}
  def defer_targeted_issue_ids(_issue_ids, _details, %Options{defer_targeted_issue_ids_fn: nil}), do: :ok

  def defer_targeted_issue_ids(issue_ids, details, %Options{} = options) when is_list(issue_ids) and is_list(details) do
    args =
      if is_function(options.defer_targeted_issue_ids_fn, 2) do
        [issue_ids, details]
      else
        [issue_ids]
      end

    options.defer_targeted_issue_ids_fn
    |> safe_call(:defer_targeted_issue_ids, args)
    |> normalize_defer_result()
  end

  @spec emit_event(atom(), atom(), map(), Options.t()) :: :ok | {:error, term()}
  def emit_event(level, event, fields, %Options{} = options)
      when is_atom(level) and is_atom(event) and is_map(fields) do
    case safe_call(options.emit_event_fn, :emit_event, [level, event, fields]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_call(fun, operation, args) when is_function(fun) and is_atom(operation) and is_list(args) do
    {:ok, apply(fun, args)}
  rescue
    error ->
      {:error, {:reconciler_callback_failed, Diagnostics.callback_exception(operation, error)}}
  catch
    kind, reason ->
      {:error, {:reconciler_callback_failed, Diagnostics.callback_failed(operation, kind, reason)}}
  end

  defp normalize_tagged_result({:ok, {:ok, result}}, _operation), do: {:ok, result}
  defp normalize_tagged_result({:ok, {:error, reason}}, _operation), do: {:error, reason}
  defp normalize_tagged_result({:ok, other}, operation), do: {:error, {:invalid_reconciler_client_result, Diagnostics.invalid_result(operation, other)}}
  defp normalize_tagged_result({:error, reason}, _operation), do: {:error, reason}

  defp normalize_optional_ok_result({:ok, {:ok, result}}, _operation), do: {:ok, result}
  defp normalize_optional_ok_result({:ok, {:error, reason}}, _operation), do: {:error, reason}
  defp normalize_optional_ok_result({:ok, result}, _operation), do: {:ok, result}
  defp normalize_optional_ok_result({:error, reason}, _operation), do: {:error, reason}

  defp normalize_defer_result({:ok, {:ok, result}}), do: {:ok, result}
  defp normalize_defer_result({:ok, :ok}), do: :ok
  defp normalize_defer_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_defer_result({:ok, other}), do: {:error, {:invalid_reconciler_client_result, Diagnostics.invalid_result(:defer_targeted_issue_ids, other)}}
  defp normalize_defer_result({:error, reason}), do: {:error, reason}
end
