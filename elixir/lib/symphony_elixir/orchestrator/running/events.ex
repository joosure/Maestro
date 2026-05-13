defmodule SymphonyElixir.Orchestrator.Running.Events do
  @moduledoc false

  alias SymphonyElixir.Issue

  @spec issue_reconcile(keyword(), atom(), atom(), Issue.t(), map(), map()) :: :ok
  def issue_reconcile(opts, level, event, %Issue{} = issue, state, extra_fields)
      when is_map(extra_fields) do
    case Keyword.get(opts, :emit_issue_reconcile_event) do
      emit_issue_reconcile_event when is_function(emit_issue_reconcile_event, 5) ->
        emit_issue_reconcile_event.(level, event, issue, state, extra_fields)

      _other ->
        emit(opts, level, event, issue, state, Map.put(extra_fields, :current_state, issue.state))
    end
  end

  def issue_reconcile(_opts, _level, _event, _issue, _state, _extra_fields), do: :ok

  @spec emit(keyword(), atom(), atom(), term(), map(), map()) :: :ok
  def emit(opts, level, event, issue, state, extra_fields) when is_map(extra_fields) do
    case Keyword.get(opts, :emit_event) do
      emit_event when is_function(emit_event, 5) ->
        emit_event.(level, event, issue, state, extra_fields)

      _other ->
        :ok
    end
  end
end
