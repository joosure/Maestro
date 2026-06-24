defmodule SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata do
  @moduledoc false

  @run_id "run_id"
  @issue_id "issue_id"
  @issue_identifier "issue_identifier"
  @agent_provider_kind "agent_provider_kind"
  @session_id "session_id"
  @thread_id "thread_id"
  @turn_id "turn_id"
  @worker_host "worker_host"

  @key_by_atom %{
    run_id: @run_id,
    issue_id: @issue_id,
    issue_identifier: @issue_identifier,
    agent_provider_kind: @agent_provider_kind,
    session_id: @session_id,
    thread_id: @thread_id,
    turn_id: @turn_id,
    worker_host: @worker_host
  }

  @type t :: %{String.t() => term()}

  @spec run_id_key() :: String.t()
  def run_id_key, do: @run_id

  @spec issue_id_key() :: String.t()
  def issue_id_key, do: @issue_id

  @spec issue_identifier_key() :: String.t()
  def issue_identifier_key, do: @issue_identifier

  @spec agent_provider_kind_key() :: String.t()
  def agent_provider_kind_key, do: @agent_provider_kind

  @spec session_id_key() :: String.t()
  def session_id_key, do: @session_id

  @spec thread_id_key() :: String.t()
  def thread_id_key, do: @thread_id

  @spec turn_id_key() :: String.t()
  def turn_id_key, do: @turn_id

  @spec worker_host_key() :: String.t()
  def worker_host_key, do: @worker_host

  @spec key(atom() | String.t()) :: String.t()
  def key(field) when is_atom(field), do: Map.get(@key_by_atom, field, Atom.to_string(field))
  def key(field) when is_binary(field), do: field

  @spec normalize(term()) :: {:ok, t()} | :error
  def normalize(metadata) when is_map(metadata) do
    metadata
    |> Enum.reduce_while(%{}, fn {key, value}, acc ->
      case normalize_key(key) do
        key when is_binary(key) -> {:cont, Map.put(acc, key, value)}
        nil -> {:halt, :error}
      end
    end)
    |> case do
      metadata when is_map(metadata) -> {:ok, metadata}
      :error -> :error
    end
  end

  def normalize(_metadata), do: :error

  @spec empty() :: t()
  def empty, do: %{}

  @spec value(t(), atom() | String.t()) :: term()
  def value(metadata, field) when is_map(metadata) do
    Map.get(metadata, key(field))
  end

  @spec put(t(), atom(), term()) :: t()
  def put(metadata, field, value) when is_map(metadata) and is_atom(field) and is_binary(value) do
    case String.trim(value) do
      "" -> metadata
      normalized -> Map.put_new(metadata, key(field), normalized)
    end
  end

  def put(metadata, _field, _value) when is_map(metadata), do: metadata

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_key), do: nil
end
