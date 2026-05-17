defmodule SymphonyWorkerDaemon.Session.Ledger.Persistence do
  @moduledoc false

  require Logger

  alias SymphonyWorkerDaemon.Protocol.Fields, as: ProtocolFields
  alias SymphonyWorkerDaemon.Session.Ledger.{Health, Summary}

  @session_id_key ProtocolFields.session_id()

  @spec normalize_path(term()) :: String.t() | nil
  def normalize_path(nil), do: nil

  def normalize_path(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_path(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_path()
  def normalize_path(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_path(_value), do: nil

  @spec load(String.t() | nil) :: {Summary.sessions(), Health.t()}
  def load(nil), do: {%{}, Health.ready(nil)}

  def load(path) when is_binary(path) do
    case File.read(path) do
      {:ok, data} ->
        decode_sessions(path, data)

      {:error, :enoent} ->
        {%{}, Health.ready(path)}

      {:error, reason} ->
        Logger.warning("worker_daemon_session_ledger_load_failed path=#{inspect(path)} reason=#{inspect(reason)}")
        {%{}, Health.degraded(path, :load, reason)}
    end
  end

  @spec persist(map()) :: map()
  def persist(%{path: nil} = state), do: Map.put(state, :health, Health.ready(nil))

  def persist(%{path: path, sessions: sessions} = state) when is_binary(path) do
    payload = Jason.encode!(%{"sessions" => Map.values(sessions)})
    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, payload),
         :ok <- chmod_private(tmp_path),
         :ok <- File.rename(tmp_path, path) do
      Map.put(state, :health, Health.ready(path))
    else
      reason ->
        File.rm(tmp_path)
        Logger.error("worker_daemon_session_ledger_persist_failed path=#{inspect(path)} reason=#{inspect(reason)}")
        Map.put(state, :health, Health.degraded(path, :persist, reason))
    end
  end

  defp decode_sessions(path, data) when is_binary(path) and is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"sessions" => sessions}} when is_list(sessions) ->
        loaded_sessions =
          sessions
          |> Enum.filter(&is_map/1)
          |> Enum.map(&Summary.normalize/1)
          |> Enum.filter(&Map.has_key?(&1, @session_id_key))
          |> Map.new(fn summary -> {Map.fetch!(summary, @session_id_key), summary} end)

        {loaded_sessions, Health.ready(path)}

      {:ok, _payload} ->
        Logger.warning("worker_daemon_session_ledger_invalid_shape path=#{inspect(path)}")
        {%{}, Health.degraded(path, :decode, :invalid_shape)}

      {:error, reason} ->
        Logger.warning("worker_daemon_session_ledger_decode_failed path=#{inspect(path)} reason=#{inspect(reason)}")
        {%{}, Health.degraded(path, :decode, reason)}
    end
  end

  defp chmod_private(path) when is_binary(path) do
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end
end
