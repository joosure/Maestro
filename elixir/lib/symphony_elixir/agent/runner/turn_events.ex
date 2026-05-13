defmodule SymphonyElixir.Agent.Runner.TurnEvents do
  @moduledoc false

  alias SymphonyElixir.Agent.FailureClassifier
  alias SymphonyElixir.AgentProvider.Error, as: ProviderError
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @spec terminal_event_for_status(term()) :: atom()
  def terminal_event_for_status(:completed), do: :agent_turn_completed
  def terminal_event_for_status(:timeout), do: :agent_turn_timeout
  def terminal_event_for_status(:input_required), do: :agent_turn_input_required
  def terminal_event_for_status(:failed), do: :agent_turn_failed
  def terminal_event_for_status(:cancelled), do: :agent_turn_failed
  def terminal_event_for_status(_status), do: :agent_turn_completed

  @spec terminal_event_for_error(term()) :: atom()
  def terminal_event_for_error(:turn_timeout), do: :agent_turn_timeout
  def terminal_event_for_error(:response_timeout), do: :agent_turn_timeout
  def terminal_event_for_error({:turn_input_required, _payload}), do: :agent_turn_input_required
  def terminal_event_for_error({:approval_required, _payload}), do: :agent_turn_input_required

  def terminal_event_for_error(%ProviderError{code: code}) do
    code
    |> Atom.to_string()
    |> terminal_event_for_error_code()
  end

  def terminal_event_for_error(_reason), do: :agent_turn_failed

  @spec terminal_level(atom()) :: :info | :warning | :error
  def terminal_level(:agent_turn_completed), do: :info
  def terminal_level(:agent_turn_input_required), do: :warning
  def terminal_level(:agent_turn_timeout), do: :error
  def terminal_level(:agent_turn_failed), do: :error

  @spec status_string(term()) :: String.t()
  def status_string(nil), do: "completed"
  def status_string(status) when is_atom(status), do: Atom.to_string(status)
  def status_string(status) when is_binary(status), do: status
  def status_string(_status), do: "completed"

  @spec status_for_event(atom()) :: String.t()
  def status_for_event(:agent_turn_timeout), do: "timeout"
  def status_for_event(:agent_turn_input_required), do: "input_required"
  def status_for_event(:agent_turn_failed), do: "failed"

  @spec status_error_fields(term()) :: map()
  def status_error_fields(:completed), do: %{}
  def status_error_fields(:input_required), do: %{failure_class: "input_required", retryable: false}
  def status_error_fields(:timeout), do: %{failure_class: "timeout", retryable: true}
  def status_error_fields(:failed), do: %{failure_class: "agent_provider_failure"}
  def status_error_fields(:cancelled), do: %{failure_class: "cancelled", retryable: false}
  def status_error_fields(_status), do: %{}

  @spec error_fields(term()) :: map()
  def error_fields(%ProviderError{} = error) do
    %{
      agent_provider_kind: error.provider,
      failure_class: failure_class(error),
      error_code: error.code,
      operation: error.operation || "run_turn",
      retryable: error.retryable?,
      error: error.message
    }
  end

  def error_fields(reason) do
    reason
    |> ObsLogger.error_details()
    |> Map.merge(%{
      failure_class: failure_class(reason),
      error_code: error_code(reason),
      retryable: retryable?(reason)
    })
  end

  @spec failure_class(term()) :: String.t()
  def failure_class(%ProviderError{code: code}) when is_atom(code) do
    code_string = Atom.to_string(code)

    cond do
      String.contains?(code_string, "timeout") -> "timeout"
      String.contains?(code_string, "input_required") -> "input_required"
      true -> "agent_provider_failure"
    end
  end

  def failure_class(:turn_timeout), do: "timeout"
  def failure_class(:response_timeout), do: "timeout"
  def failure_class({:agent_turn_terminal_status, :timeout}), do: "timeout"
  def failure_class({:agent_turn_terminal_status, :input_required}), do: "input_required"
  def failure_class({:agent_turn_terminal_status, :cancelled}), do: "cancelled"
  def failure_class({:agent_turn_terminal_status, :failed}), do: "agent_provider_failure"
  def failure_class({:turn_input_required, _payload}), do: "input_required"
  def failure_class({:approval_required, _payload}), do: "input_required"
  def failure_class({:turn_cancelled, _payload}), do: "cancelled"
  def failure_class(_reason), do: "agent_provider_failure"

  @spec run_failure_class(term(), String.t() | nil) :: String.t()
  def run_failure_class(reason, worker_host) do
    FailureClassifier.classify_worker_failure(reason, worker_host) ||
      failure_class(reason) ||
      "agent_run_failure"
  end

  @spec provider_error_fields(term()) :: map()
  def provider_error_fields(%ProviderError{} = error) do
    %{
      agent_provider_kind: error.provider,
      error_code: error.code,
      operation: error.operation,
      retryable: error.retryable?,
      error: error.message
    }
  end

  def provider_error_fields(_reason), do: %{}

  defp terminal_event_for_error_code(code) when is_binary(code) do
    cond do
      String.contains?(code, "timeout") -> :agent_turn_timeout
      String.contains?(code, "input_required") -> :agent_turn_input_required
      true -> :agent_turn_failed
    end
  end

  defp error_code(%ProviderError{code: code}), do: code
  defp error_code(:turn_timeout), do: :turn_timeout
  defp error_code(:response_timeout), do: :response_timeout
  defp error_code({:agent_turn_terminal_status, status}), do: status
  defp error_code({:turn_input_required, _payload}), do: :turn_input_required
  defp error_code({:approval_required, _payload}), do: :approval_required
  defp error_code({:turn_cancelled, _payload}), do: :turn_cancelled
  defp error_code(_reason), do: :agent_turn_failed

  defp retryable?(%ProviderError{retryable?: retryable}), do: retryable
  defp retryable?(:turn_timeout), do: true
  defp retryable?(:response_timeout), do: true
  defp retryable?(_reason), do: false
end
