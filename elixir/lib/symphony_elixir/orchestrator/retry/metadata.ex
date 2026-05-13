defmodule SymphonyElixir.Orchestrator.Retry.Metadata do
  @moduledoc false

  alias SymphonyElixir.Config

  @spec build_entry(String.t(), map(), map(), integer(), reference(), reference(), integer()) :: map()
  def build_entry(issue_id, previous_retry, metadata, attempt, timer_ref, retry_token, due_at_ms)
      when is_binary(issue_id) and is_map(previous_retry) and is_map(metadata) and is_integer(attempt) and
             is_reference(timer_ref) and is_reference(retry_token) and is_integer(due_at_ms) do
    %{
      attempt: attempt,
      timer_ref: timer_ref,
      retry_token: retry_token,
      due_at_ms: due_at_ms,
      identifier: identifier(issue_id, previous_retry, metadata),
      error: error(previous_retry, metadata),
      run_id: run_id(previous_retry, metadata),
      agent_provider_kind: agent_provider_kind(previous_retry, metadata),
      worker_host: worker_host(previous_retry, metadata),
      workspace_path: workspace_path(previous_retry, metadata),
      failure_class: failure_class(previous_retry, metadata),
      delay_type: delay_type(metadata)
    }
  end

  @spec from_entry(map()) :: map()
  def from_entry(retry_entry) when is_map(retry_entry) do
    %{
      identifier: Map.get(retry_entry, :identifier),
      error: Map.get(retry_entry, :error),
      run_id: Map.get(retry_entry, :run_id),
      agent_provider_kind: Map.get(retry_entry, :agent_provider_kind),
      worker_host: Map.get(retry_entry, :worker_host),
      workspace_path: Map.get(retry_entry, :workspace_path),
      failure_class: Map.get(retry_entry, :failure_class)
    }
  end

  def from_entry(_retry_entry), do: %{}

  defp identifier(issue_id, previous_retry, metadata) do
    metadata[:identifier] || Map.get(previous_retry, :identifier) || issue_id
  end

  defp run_id(previous_retry, metadata) do
    metadata[:run_id] || Map.get(previous_retry, :run_id)
  end

  defp error(previous_retry, metadata) do
    metadata[:error] || Map.get(previous_retry, :error)
  end

  defp worker_host(previous_retry, metadata) do
    metadata[:worker_host] || Map.get(previous_retry, :worker_host)
  end

  defp workspace_path(previous_retry, metadata) do
    metadata[:workspace_path] || Map.get(previous_retry, :workspace_path)
  end

  defp failure_class(previous_retry, metadata) do
    metadata[:failure_class] || Map.get(previous_retry, :failure_class)
  end

  defp delay_type(metadata), do: metadata[:delay_type]

  defp agent_provider_kind(previous_retry, metadata) do
    metadata[:agent_provider_kind] || Map.get(previous_retry, :agent_provider_kind) ||
      Config.agent_provider_kind()
  end
end
