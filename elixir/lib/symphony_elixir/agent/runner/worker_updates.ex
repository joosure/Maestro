defmodule SymphonyElixir.Agent.Runner.WorkerUpdates do
  @moduledoc false

  alias SymphonyElixir.Agent.Runtime
  alias SymphonyElixir.{AgentProvider, Issue}

  @type worker_host :: String.t() | nil

  @spec message_handler(term(), term()) :: (term() -> :ok)
  def message_handler(recipient, issue) do
    agent_provider_kind = AgentProvider.current_kind()

    fn message ->
      message = tag_agent_provider(message, agent_provider_kind)
      send_agent_update(recipient, issue, message)
    end
  end

  @spec runtime_info(term(), term(), worker_host(), Path.t() | nil, String.t()) :: :ok
  @spec runtime_info(
          term(),
          term(),
          worker_host(),
          Path.t() | nil,
          String.t(),
          Runtime.worker_runtime_info()
        ) :: :ok
  def runtime_info(recipient, issue, worker_host, workspace, run_id, extra \\ %{})

  def runtime_info(recipient, %Issue{id: issue_id}, worker_host, workspace, run_id, extra)
      when is_binary(issue_id) and is_pid(recipient) and is_map(extra) do
    send(
      recipient,
      {:worker_runtime_info, issue_id,
       Map.merge(
         %{
           run_id: run_id,
           agent_provider_kind: AgentProvider.current_kind(),
           worker_host: worker_host,
           workspace_path: workspace
         },
         extra
       )}
    )

    :ok
  end

  def runtime_info(_recipient, _issue, _worker_host, _workspace, _run_id, _extra), do: :ok

  defp send_agent_update(recipient, %Issue{id: issue_id}, message)
       when is_binary(issue_id) and is_pid(recipient) do
    send(recipient, {worker_update_message(message), issue_id, message})
    :ok
  end

  defp send_agent_update(_recipient, _issue, _message), do: :ok

  defp worker_update_message(%{agent_provider_kind: provider}) when is_binary(provider),
    do: :agent_worker_update

  defp worker_update_message(_message), do: :agent_worker_update

  defp tag_agent_provider(message, agent_provider_kind)
       when is_map(message) and is_binary(agent_provider_kind) do
    Map.put_new(message, :agent_provider_kind, agent_provider_kind)
  end

  defp tag_agent_provider(message, _agent_provider_kind), do: message
end
