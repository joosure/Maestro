defmodule SymphonyWorkerDaemon.Protocol.Paths do
  @moduledoc false

  alias SymphonyWorkerDaemon.Protocol.QueryParams

  @base_path "/api/v1/worker-daemon"

  @spec base_path() :: String.t()
  def base_path, do: @base_path

  @spec health_path() :: String.t()
  def health_path, do: @base_path <> "/health"

  @spec sessions_path() :: String.t()
  def sessions_path, do: @base_path <> "/sessions"

  @spec sessions_path(map() | keyword()) :: String.t()
  def sessions_path(filters) when is_map(filters) or is_list(filters) do
    case QueryParams.session(filters) do
      "" -> sessions_path()
      query -> sessions_path() <> "?" <> query
    end
  end

  @spec session_path(String.t()) :: String.t()
  def session_path(session_id) when is_binary(session_id), do: sessions_path() <> "/" <> URI.encode(session_id)

  @spec input_path(String.t()) :: String.t()
  def input_path(session_id) when is_binary(session_id), do: session_path(session_id) <> "/input"

  @spec stop_path(String.t()) :: String.t()
  def stop_path(session_id) when is_binary(session_id), do: session_path(session_id) <> "/stop"

  @spec cleanup_path(String.t()) :: String.t()
  def cleanup_path(session_id) when is_binary(session_id), do: session_path(session_id) <> "/cleanup"

  @spec events_path(String.t()) :: String.t()
  def events_path(session_id) when is_binary(session_id), do: session_path(session_id) <> "/events"

  @spec events_path(String.t(), map() | keyword()) :: String.t()
  def events_path(session_id, filters) when is_binary(session_id) and (is_map(filters) or is_list(filters)) do
    case QueryParams.events(filters) do
      "" -> events_path(session_id)
      query -> events_path(session_id) <> "?" <> query
    end
  end
end
