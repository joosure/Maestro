defmodule SymphonyElixir.Agent.Runner.EventFields do
  @moduledoc false

  alias SymphonyElixir.{AgentProvider, Tracker}

  @type worker_host :: String.t() | nil

  @spec event(term(), worker_host(), Path.t() | nil, map()) :: map()
  def event(issue, worker_host, workspace, extra) when is_map(extra) do
    %{
      component: "agent_runner",
      agent_provider_kind: AgentProvider.current_kind(),
      tracker_kind: Tracker.current_kind(),
      issue_id: Map.get(issue, :id),
      issue_identifier: Map.get(issue, :identifier),
      worker_host: worker_host,
      workspace_path: workspace
    }
    |> Map.merge(extra)
  end

  @spec turn(term(), term(), worker_host(), Path.t() | nil, String.t(), pos_integer(), pos_integer(), map()) :: map()
  def turn(session, issue, worker_host, workspace, run_id, turn_number, max_turns, extra)
      when is_map(extra) do
    session_id = Map.get(extra, :session_id) || session_value(session, :session_id)
    thread_id = Map.get(extra, :thread_id) || session_value(session, :thread_id)
    turn_id = Map.get(extra, :turn_id)

    issue
    |> event(worker_host, workspace, %{
      run_id: run_id,
      correlation_id: run_id,
      attempt: turn_number,
      turn_number: turn_number,
      max_turns: max_turns,
      session_id: session_id,
      thread_id: thread_id,
      turn_id: turn_id
    })
    |> Map.merge(extra)
  end

  @spec prompt_observability_fields(String.t()) :: map()
  def prompt_observability_fields(prompt) when is_binary(prompt) do
    %{
      prompt_hash: prompt_hash(prompt),
      prompt_length: byte_size(prompt)
    }
  end

  @spec session_value(term(), atom()) :: term()
  def session_value(session, key) when is_map(session), do: Map.get(session, key)
  def session_value(_session, _key), do: nil

  defp prompt_hash(prompt) when is_binary(prompt) do
    :crypto.hash(:sha256, prompt)
    |> Base.encode16(case: :lower)
  end
end
