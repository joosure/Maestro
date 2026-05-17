defmodule SymphonyElixir.AgentProvider.Codex.EventMapper do
  @moduledoc false

  alias SymphonyElixir.AgentProvider.Codex.EventSummaryMapper.Payload
  alias SymphonyElixir.AgentProvider.Event
  alias SymphonyElixir.AgentProvider.Kinds

  @provider_kind Kinds.codex()

  @spec map_message(term()) :: Event.t()
  def map_message(nil), do: Event.new(agent_provider_kind: @provider_kind, raw: nil)

  def map_message(%{event: event, message: message} = raw) do
    message
    |> Payload.unwrap_message_payload()
    |> base_event(raw)
    |> Event.put_if_present(:event, event)
    |> Event.put_if_present(:timestamp, Map.get(raw, :timestamp))
  end

  def map_message(%{message: message} = raw) do
    message
    |> Payload.unwrap_message_payload()
    |> base_event(raw)
    |> Event.put_if_present(:timestamp, Map.get(raw, :timestamp))
  end

  def map_message(message) do
    message
    |> Payload.unwrap_message_payload()
    |> base_event(message)
  end

  defp base_event(payload, raw) do
    Event.new(agent_provider_kind: @provider_kind, payload: payload, raw: raw)
    |> put_session_id(payload)
  end

  defp put_session_id(event, payload) do
    session_id =
      case payload do
        %{} -> Map.get(payload, "session_id") || Map.get(payload, :session_id)
        _ -> nil
      end

    Event.put_if_present(event, :session_id, session_id)
  end
end
