defmodule SymphonyWorkerDaemon.OrphanSweeper.LedgerRecorder do
  @moduledoc false

  alias SymphonyWorkerDaemon.Session.Ledger

  @spec record(GenServer.server() | nil, map(), map()) :: :ok
  def record(ledger, session, attrs) when is_map(session) and is_map(attrs) do
    Ledger.record_session_sync(
      ledger,
      session
      |> Map.merge(attrs)
      |> Map.put("orphan_swept_at_ms", now_ms())
      |> Map.put("updated_at_ms", now_ms())
    )
  end

  defp now_ms, do: System.system_time(:millisecond)
end
