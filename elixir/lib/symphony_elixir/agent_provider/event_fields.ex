defmodule SymphonyElixir.AgentProvider.EventFields do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Config
  alias SymphonyElixir.AgentProvider.Error
  alias SymphonyElixir.AgentProvider.Session
  alias SymphonyElixir.Observability.Logger, as: ObsLogger

  @spec monotonic_ms() :: integer()
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @spec elapsed_ms(integer()) :: non_neg_integer()
  def elapsed_ms(started_at_ms), do: max(monotonic_ms() - started_at_ms, 0)

  @spec session(Session.t(), Config.t(), keyword(), map()) :: map()
  def session(%Session{} = session, %Config{} = config, opts, extra)
      when is_list(opts) and is_map(extra) do
    issue = Keyword.get(opts, :issue)

    %{
      component: "agent_provider",
      agent_provider_kind: session.agent_provider_kind || config.kind,
      run_id: session.run_id || Keyword.get(opts, :run_id),
      correlation_id: session.run_id || Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(issue, :id),
      issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(issue, :identifier),
      session_id: session.session_id,
      thread_id: session.thread_id,
      worker_host: session.worker_host || Keyword.get(opts, :worker_host),
      workspace_path: session.workspace || Keyword.get(opts, :workspace)
    }
    |> Map.merge(extra)
  end

  @spec workspace(Config.t(), Path.t(), keyword(), map()) :: map()
  def workspace(%Config{} = config, workspace, opts, extra)
      when is_binary(workspace) and is_list(opts) and is_map(extra) do
    issue = Keyword.get(opts, :issue)

    %{
      component: "agent_provider",
      agent_provider_kind: config.kind,
      run_id: Keyword.get(opts, :run_id),
      correlation_id: Keyword.get(opts, :run_id),
      issue_id: Keyword.get(opts, :issue_id) || map_value(issue, :id),
      issue_identifier: Keyword.get(opts, :issue_identifier) || map_value(issue, :identifier),
      worker_host: Keyword.get(opts, :worker_host),
      workspace_path: workspace
    }
    |> Map.merge(extra)
  end

  @spec error(Error.t() | term()) :: map()
  def error(%Error{} = error) do
    %{
      agent_provider_kind: error.provider,
      operation: error.operation,
      error_code: error.code,
      retryable: error.retryable?,
      error: error.message
    }
  end

  def error(reason), do: ObsLogger.error_details(reason)

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil
end
