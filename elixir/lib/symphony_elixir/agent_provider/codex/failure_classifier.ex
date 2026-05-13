defmodule SymphonyElixir.AgentProvider.Codex.FailureClassifier do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Error

  @spec session_stop_options(term(), term()) :: keyword()
  def session_stop_options({:error, reason}, issue) do
    if session_failure_reason?(reason) do
      failed_session_stop_options(issue, inspect(reason))
    else
      [issue: issue]
    end
  end

  def session_stop_options(_result, issue), do: [issue: issue]

  @spec failed_session_stop_options(term(), String.t()) :: keyword()
  def failed_session_stop_options(issue, error) when is_binary(error) do
    [status: :failed, issue: issue, extra: %{error: error}]
  end

  defp session_failure_reason?(:turn_timeout), do: true
  defp session_failure_reason?(:response_timeout), do: true
  defp session_failure_reason?({:port_exit, _status}), do: true
  defp session_failure_reason?({:response_error, _error}), do: true
  defp session_failure_reason?({:turn_failed, _payload}), do: true
  defp session_failure_reason?({:turn_cancelled, _payload}), do: true
  defp session_failure_reason?({:turn_input_required, _payload}), do: true
  defp session_failure_reason?({:approval_required, _payload}), do: true
  defp session_failure_reason?({:codex_error, _payload}), do: true
  defp session_failure_reason?(%Error{}), do: true
  defp session_failure_reason?(_reason), do: false
end
