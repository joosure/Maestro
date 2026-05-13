defmodule SymphonyElixir.AgentProvider.Codex.AppServer.EventFields do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.AppServer.EventFields, as: AppServerEventFields
  alias SymphonyElixir.Tracker

  @spec event(Path.t() | nil, String.t() | nil, map() | nil, map()) :: map()
  def event(workspace, worker_host, issue, extra) when is_map(extra) do
    AppServerEventFields.build(base_fields(), workspace, worker_host, issue, extra)
  end

  @spec turn(map() | nil, map()) :: map()
  def turn(nil, extra), do: event(nil, nil, nil, extra)

  def turn(turn_context, extra) when is_map(turn_context) and is_map(extra) do
    AppServerEventFields.turn(base_fields(), turn_context, extra)
  end

  @spec prompt_hash(String.t() | term()) :: non_neg_integer() | nil
  def prompt_hash(prompt), do: AppServerEventFields.prompt_hash(prompt)

  @spec stream_summary(term()) :: String.t()
  def stream_summary(payload), do: AppServerEventFields.stream_summary(payload)

  defp base_fields do
    %{
      component: "codex.app_server",
      tracker_kind: Tracker.current_kind()
    }
  end
end
