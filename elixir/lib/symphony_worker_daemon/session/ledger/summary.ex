defmodule SymphonyWorkerDaemon.Session.Ledger.Summary do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol

  @type sessions :: %{optional(String.t()) => map()}

  @spec normalize(map()) :: map()
  def normalize(summary) when is_map(summary) do
    summary
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> compact_map()
  end

  @spec put(sessions(), map()) :: sessions()
  def put(sessions, summary) when is_map(sessions) and is_map(summary) do
    case normalize(summary) do
      %{"session_id" => session_id} = summary -> Map.put(sessions, session_id, summary)
      _invalid -> sessions
    end
  end

  @spec fetch(sessions(), String.t()) :: {:ok, map()} | {:error, :session_not_found}
  def fetch(sessions, session_id) when is_map(sessions) and is_binary(session_id) do
    case Map.fetch(sessions, session_id) do
      {:ok, summary} -> {:ok, summary}
      :error -> {:error, :session_not_found}
    end
  end

  @spec mark_cleaned(map(), non_neg_integer()) :: map()
  def mark_cleaned(summary, updated_at_ms) when is_map(summary) and is_integer(updated_at_ms) do
    summary
    |> Map.put("status", "cleaned")
    |> Map.put("updated_at_ms", updated_at_ms)
  end

  @spec mark_active_lost(sessions(), term(), non_neg_integer()) :: sessions()
  def mark_active_lost(sessions, reason, updated_at_ms) when is_map(sessions) and is_integer(updated_at_ms) do
    Map.new(sessions, fn {session_id, summary} ->
      if terminal?(Map.get(summary, "status")) do
        {session_id, summary}
      else
        {session_id,
         summary
         |> Map.put("status", "lost")
         |> Map.put("lost_reason", normalize_lost_reason(reason))
         |> Map.put("updated_at_ms", updated_at_ms)}
      end
    end)
  end

  defp terminal?(status) when is_binary(status), do: Protocol.terminal_status?(status)
  defp terminal?(_status), do: false

  defp normalize_lost_reason(reason) when is_binary(reason), do: reason
  defp normalize_lost_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_lost_reason(reason), do: inspect(reason)

  defp compact_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
