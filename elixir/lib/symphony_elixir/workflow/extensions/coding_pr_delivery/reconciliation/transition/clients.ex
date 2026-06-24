defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Clients do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.TrackerCallOptions
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Diagnostics
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Transition.Options

  @spec fetch_issue_states_by_ids([String.t()], Options.t()) :: {:ok, list()} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids, %Options{} = options) when is_list(issue_ids) do
    options.fetch_issue_states_by_ids_fn
    |> safe_call(:fetch_issue_states_by_ids, [issue_ids, TrackerCallOptions.fetch(options.raw_opts)])
    |> normalize_fetch_result(:fetch_issue_states_by_ids)
  end

  @spec update_issue_state(String.t(), String.t(), String.t() | nil, Options.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, target_state, expected_current_state, %Options{} = options)
      when is_binary(issue_id) and is_binary(target_state) do
    write_opts =
      options.raw_opts
      |> TrackerCallOptions.write()
      |> Keyword.put(:expected_current_state, expected_current_state)

    options.update_issue_state_fn
    |> safe_call(:update_issue_state, [issue_id, target_state, write_opts])
    |> normalize_update_result(:update_issue_state)
  end

  defp safe_call(fun, operation, args) when is_function(fun) and is_atom(operation) and is_list(args) do
    {:ok, apply(fun, args)}
  rescue
    error ->
      {:error, {:transition_callback_failed, Diagnostics.callback_exception(operation, error)}}
  catch
    kind, reason ->
      {:error, {:transition_callback_failed, Diagnostics.callback_failed(operation, kind, reason)}}
  end

  defp normalize_fetch_result({:ok, {:ok, result}}, _operation) when is_list(result), do: {:ok, result}
  defp normalize_fetch_result({:ok, {:ok, result}}, operation), do: {:error, {:invalid_transition_client_result, Diagnostics.invalid_result(operation, result)}}
  defp normalize_fetch_result({:ok, {:error, reason}}, _operation), do: {:error, reason}
  defp normalize_fetch_result({:ok, other}, operation), do: {:error, {:invalid_transition_client_result, Diagnostics.invalid_result(operation, other)}}
  defp normalize_fetch_result({:error, reason}, _operation), do: {:error, reason}

  defp normalize_update_result({:ok, :ok}, _operation), do: :ok
  defp normalize_update_result({:ok, {:error, reason}}, _operation), do: {:error, reason}
  defp normalize_update_result({:ok, other}, operation), do: {:error, {:invalid_transition_client_result, Diagnostics.invalid_result(operation, other)}}
  defp normalize_update_result({:error, reason}, _operation), do: {:error, reason}
end
