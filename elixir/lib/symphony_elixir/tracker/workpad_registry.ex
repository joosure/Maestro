defmodule SymphonyElixir.Tracker.WorkpadRegistry do
  @moduledoc """
  Registry for tracker workpad identities.

  This registry is the internal source of truth for issue/workpad identities.
  Tracker adapters record a stable workpad `id` plus the provider-native storage
  reference returned by typed tool writes and read it back on later turns, so
  runtime behavior does not depend on parsing tracker comment titles, Markdown
  sections, or prompt-authored text.
  """

  use GenServer

  alias SymphonyElixir.Workflow

  @default_relative_path [".symphony", "tracker_workpads.json"]

  defmodule State do
    @moduledoc false

    defstruct records: %{}, persistence_path: nil
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, Keyword.delete(opts, :name))
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @spec register(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def register(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, {:error, :workpad_registry_unavailable}, fn ->
      GenServer.call(server, {:register, attrs, opts})
    end)
  end

  @spec get(String.t(), String.t(), keyword()) :: map() | nil
  def get(tracker_kind, issue_id, opts \\ []) when is_binary(tracker_kind) and is_binary(issue_id) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, nil, fn ->
      GenServer.call(server, {:get, tracker_kind, issue_id})
    end)
  end

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, :ok, fn ->
      GenServer.call(server, :reset)
    end)
  end

  @impl true
  def init(opts) do
    state = %State{persistence_path: persistence_path(opts)}
    {:ok, load_persisted_records(state)}
  end

  @impl true
  def handle_call({:register, attrs, opts}, _from, %State{} = state) do
    case normalize_record(attrs, opts) do
      {:ok, record} ->
        state = put_record(state, record)
        persist_records(state)
        {:reply, {:ok, record}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get, tracker_kind, issue_id}, _from, %State{} = state) do
    {:reply, Map.get(state.records, record_key(tracker_kind, issue_id)), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    remove_persisted_records(state)
    {:reply, :ok, %{state | records: %{}}}
  end

  defp normalize_record(attrs, opts) do
    tracker_kind = string_value(attrs, "tracker_kind") || string_value(attrs, :tracker_kind)
    issue_id = string_value(attrs, "issue_id") || string_value(attrs, :issue_id)
    workpad_id = string_value(attrs, "id") || string_value(attrs, :id)
    provider_ref = provider_ref(attrs)

    cond do
      blank?(tracker_kind) -> {:error, {:invalid_workpad_record, :missing_tracker_kind}}
      blank?(issue_id) -> {:error, {:invalid_workpad_record, :missing_issue_id}}
      blank?(workpad_id) -> {:error, {:invalid_workpad_record, :missing_id}}
      is_nil(provider_ref) -> {:error, {:invalid_workpad_record, :missing_provider_ref}}
      true -> {:ok, record_map(attrs, tracker_kind, issue_id, workpad_id, provider_ref, opts)}
    end
  end

  defp record_map(attrs, tracker_kind, issue_id, workpad_id, provider_ref, opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)

    %{
      "tracker_kind" => tracker_kind,
      "issue_id" => issue_id,
      "id" => workpad_id,
      "provider_ref" => provider_ref,
      "provider" => string_value(attrs, "provider") || string_value(attrs, :provider) || tracker_kind,
      "url" => string_value(attrs, "url") || string_value(attrs, :url),
      "updated_at_ms" => now_ms
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp put_record(%State{} = state, %{"tracker_kind" => tracker_kind, "issue_id" => issue_id} = record) do
    %{state | records: Map.put(state.records, record_key(tracker_kind, issue_id), record)}
  end

  defp record_key(tracker_kind, issue_id), do: tracker_kind <> ":" <> issue_id

  defp load_persisted_records(%State{persistence_path: nil} = state), do: state

  defp load_persisted_records(%State{persistence_path: path} = state) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, records} when is_list(records) <- Jason.decode(content) do
      loaded =
        records
        |> Enum.flat_map(fn attrs ->
          case normalize_record(attrs, []) do
            {:ok, record} -> [record]
            {:error, _reason} -> []
          end
        end)
        |> Map.new(fn %{"tracker_kind" => tracker_kind, "issue_id" => issue_id} = record ->
          {record_key(tracker_kind, issue_id), record}
        end)

      %{state | records: loaded}
    else
      _reason -> state
    end
  end

  defp persist_records(%State{persistence_path: nil}), do: :ok

  defp persist_records(%State{persistence_path: path, records: records}) when is_binary(path) do
    payload =
      records
      |> Map.values()
      |> Enum.sort_by(fn record -> {Map.get(record, "tracker_kind"), Map.get(record, "issue_id")} end)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(payload),
         :ok <- File.write(path, encoded) do
      :ok
    else
      _reason -> :ok
    end
  end

  defp remove_persisted_records(%State{persistence_path: nil}), do: :ok
  defp remove_persisted_records(%State{persistence_path: path}) when is_binary(path), do: File.rm(path)

  defp persistence_path(opts) do
    case Keyword.get(opts, :persistence_path, :default) do
      false -> nil
      nil -> nil
      path when is_binary(path) -> path
      :default -> default_persistence_path()
      _value -> nil
    end
  end

  defp default_persistence_path do
    Workflow.workflow_file_path()
    |> Path.dirname()
    |> Path.join(Path.join(@default_relative_path))
  rescue
    _reason -> nil
  end

  defp string_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) -> normalize_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> value |> Atom.to_string() |> normalize_string()
      _value -> nil
    end
  end

  defp provider_ref(attrs) when is_map(attrs) do
    provider_ref = Map.get(attrs, "provider_ref") || Map.get(attrs, :provider_ref)
    provider_ref_type = string_value(provider_ref || %{}, "type") || string_value(provider_ref || %{}, :type)
    provider_ref_id = string_value(provider_ref || %{}, "id") || string_value(provider_ref || %{}, :id)

    provider_ref_type =
      provider_ref_type ||
        string_value(attrs, "provider_ref_type") ||
        string_value(attrs, :provider_ref_type)

    provider_ref_id =
      provider_ref_id ||
        string_value(attrs, "provider_ref_id") ||
        string_value(attrs, :provider_ref_id)

    if blank?(provider_ref_type) or blank?(provider_ref_id) do
      nil
    else
      %{"type" => provider_ref_type, "id" => provider_ref_id}
    end
  end

  defp blank?(value), do: is_nil(value) or value == ""
  defp normalize_string(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

  defp with_server(server, fallback, fun) when is_atom(server) and is_function(fun, 0) do
    case Process.whereis(server) do
      pid when is_pid(pid) -> fun.()
      _other -> fallback
    end
  end

  defp with_server(server, _fallback, fun) when is_pid(server) and is_function(fun, 0), do: fun.()
  defp with_server(_server, fallback, _fun), do: fallback
end
