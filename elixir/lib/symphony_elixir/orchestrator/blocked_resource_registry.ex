defmodule SymphonyElixir.Orchestrator.BlockedResourceRegistry do
  @moduledoc """
  Tracks orchestrator-level non-retryable blockers by canonical resource.

  The registry is deliberately resource-based instead of issue-specific. Tracker
  issues are one resource kind, but the same lifecycle can later protect repo
  branches, change proposals, or agent sessions without changing dispatch logic.
  """

  use GenServer

  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.Workflow

  @default_relative_path [".symphony", "orchestrator_blocked_resources.json"]

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

    with_server(server, {:error, :blocked_resource_registry_unavailable}, fn ->
      GenServer.call(server, {:register, attrs, opts})
    end)
  end

  @spec active_for_issue?(String.t(), keyword()) :: boolean()
  def active_for_issue?(issue_id, opts \\ [])

  def active_for_issue?(issue_id, opts) when is_binary(issue_id) and is_list(opts) do
    not is_nil(get_active_for_issue(issue_id, opts))
  end

  def active_for_issue?(_issue_id, _opts), do: false

  @spec get_active_for_issue(String.t(), keyword()) :: map() | nil
  def get_active_for_issue(issue_id, opts \\ [])

  def get_active_for_issue(issue_id, opts) when is_binary(issue_id) and is_list(opts) do
    get_active("tracker_issue", issue_id, opts)
  end

  def get_active_for_issue(_issue_id, _opts), do: nil

  @spec get_active(String.t(), String.t(), keyword()) :: map() | nil
  def get_active(resource_kind, resource_id, opts \\ [])

  def get_active(resource_kind, resource_id, opts)
      when is_binary(resource_kind) and is_binary(resource_id) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, nil, fn ->
      GenServer.call(server, {:get_active, resource_kind, resource_id})
    end)
  end

  def get_active(_resource_kind, _resource_id, _opts), do: nil

  @spec release(String.t(), String.t(), term(), keyword()) :: :ok
  def release(resource_kind, resource_id, reason, opts \\ [])

  def release(resource_kind, resource_id, reason, opts)
      when is_binary(resource_kind) and is_binary(resource_id) and is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, :ok, fn ->
      GenServer.call(server, {:release, resource_kind, resource_id, reason, opts})
    end)
  end

  def release(_resource_kind, _resource_id, _reason, _opts), do: :ok

  @spec release_issue(String.t(), term(), keyword()) :: :ok
  def release_issue(issue_id, reason, opts \\ [])

  def release_issue(issue_id, reason, opts) when is_binary(issue_id) and is_list(opts) do
    release("tracker_issue", issue_id, reason, opts)
  end

  def release_issue(_issue_id, _reason, _opts), do: :ok

  @spec snapshot(keyword()) :: [map()]
  def snapshot(opts \\ []) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)

    with_server(server, [], fn ->
      GenServer.call(server, :snapshot)
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
        emit_registered(record)
        {:reply, {:ok, record}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get_active, resource_kind, resource_id}, _from, %State{} = state) do
    record = Map.get(state.records, record_key(resource_kind, resource_id))

    {:reply, if(active_record?(record), do: record, else: nil), state}
  end

  def handle_call({:release, resource_kind, resource_id, reason, opts}, _from, %State{} = state) do
    key = record_key(resource_kind, resource_id)

    state =
      case Map.get(state.records, key) do
        %{"status" => "active"} = record ->
          released_record = release_record(record, reason, opts)
          emit_released(released_record, reason)
          %{state | records: Map.put(state.records, key, released_record)}

        _record ->
          state
      end

    persist_records(state)
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, %State{} = state) do
    {:reply, state.records |> Map.values() |> Enum.sort_by(&snapshot_sort_key/1), state}
  end

  def handle_call(:reset, _from, %State{} = state) do
    remove_persisted_records(state)
    {:reply, :ok, %{state | records: %{}}}
  end

  defp normalize_record(attrs, opts) do
    resource_kind =
      string_value(attrs, "resource_kind") ||
        string_value(attrs, :resource_kind) ||
        get_in_string(attrs, ["resource", "kind"]) ||
        get_in_string(attrs, [:resource, :kind])

    resource_id =
      string_value(attrs, "resource_id") ||
        string_value(attrs, :resource_id) ||
        get_in_string(attrs, ["resource", "id"]) ||
        get_in_string(attrs, [:resource, :id])

    cond do
      blank?(resource_kind) -> {:error, {:invalid_blocked_resource, :missing_resource_kind}}
      blank?(resource_id) -> {:error, {:invalid_blocked_resource, :missing_resource_id}}
      true -> {:ok, record_map(attrs, resource_kind, resource_id, opts)}
    end
  end

  defp record_map(attrs, resource_kind, resource_id, opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)

    %{
      "status" => "active",
      "resource" => %{"kind" => resource_kind, "id" => resource_id},
      "issue_id" => tracker_issue_id(resource_kind, resource_id, attrs),
      "issue_identifier" => string_value(attrs, "issue_identifier") || string_value(attrs, :issue_identifier),
      "run_id" => string_value(attrs, "run_id") || string_value(attrs, :run_id),
      "session_id" => string_value(attrs, "session_id") || string_value(attrs, :session_id),
      "tool_name" => string_value(attrs, "tool_name") || string_value(attrs, :tool_name),
      "blocker_code" =>
        string_value(attrs, "blocker_code") ||
          string_value(attrs, :blocker_code) ||
          string_value(attrs, "error_code") ||
          string_value(attrs, :error_code),
      "original_error_code" => string_value(attrs, "original_error_code") || string_value(attrs, :original_error_code),
      "missing_evidence" => list_value(attrs, "missing_evidence") || list_value(attrs, :missing_evidence) || [],
      "remediation_actions" => list_value(attrs, "remediation_actions") || list_value(attrs, :remediation_actions) || [],
      "blocked_at_ms" => now_ms,
      "updated_at_ms" => now_ms
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp release_record(record, reason, opts) do
    now_ms = Keyword.get_lazy(opts, :now_ms, fn -> System.system_time(:millisecond) end)

    record
    |> Map.put("status", "released")
    |> Map.put("release_reason", reason_string(reason))
    |> Map.put("released_at_ms", now_ms)
    |> Map.put("updated_at_ms", now_ms)
  end

  defp put_record(%State{} = state, %{"resource" => %{"kind" => kind, "id" => id}} = record) do
    %{state | records: Map.put(state.records, record_key(kind, id), record)}
  end

  defp active_record?(%{"status" => "active"}), do: true
  defp active_record?(_record), do: false

  defp record_key(resource_kind, resource_id), do: resource_kind <> ":" <> resource_id

  defp snapshot_sort_key(%{"resource" => %{"kind" => kind, "id" => id}}), do: {kind, id}
  defp snapshot_sort_key(_record), do: {"", ""}

  defp load_persisted_records(%State{persistence_path: nil} = state), do: state

  defp load_persisted_records(%State{persistence_path: path} = state) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, records} when is_list(records) <- Jason.decode(content) do
      loaded =
        records
        |> Enum.flat_map(fn attrs ->
          attrs
          |> normalize_loaded_record()
          |> List.wrap()
        end)
        |> Map.new()

      %{state | records: loaded}
    else
      _reason -> state
    end
  end

  defp normalize_loaded_record(attrs) when is_map(attrs) do
    case normalize_record(attrs, []) do
      {:ok, %{"resource" => %{"kind" => kind, "id" => id}} = normalized} ->
        loaded =
          attrs
          |> Map.merge(normalized)
          |> Map.put("resource", %{"kind" => kind, "id" => id})
          |> Map.put("status", string_value(attrs, "status") || "active")

        {record_key(kind, id), loaded}

      {:error, _reason} ->
        nil
    end
  end

  defp normalize_loaded_record(_attrs), do: nil

  defp persist_records(%State{persistence_path: nil}), do: :ok

  defp persist_records(%State{persistence_path: path, records: records}) when is_binary(path) do
    payload = records |> Map.values() |> Enum.sort_by(&snapshot_sort_key/1)

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

  defp emit_registered(%{"resource" => %{"kind" => kind, "id" => id}} = record) do
    ObservabilityLogger.emit(:warning, :orchestrator_blocked_resource_registered, %{
      component: "orchestrator.blocked_resource_registry",
      issue_id: Map.get(record, "issue_id"),
      issue_identifier: Map.get(record, "issue_identifier"),
      run_id: Map.get(record, "run_id"),
      session_id: Map.get(record, "session_id"),
      resource_kind: kind,
      resource_id: id,
      blocker_code: Map.get(record, "blocker_code"),
      original_error_code: Map.get(record, "original_error_code"),
      tool_name: Map.get(record, "tool_name"),
      result_summary: "orchestrator_resource_blocked"
    })

    :ok
  end

  defp emit_released(%{"resource" => %{"kind" => kind, "id" => id}} = record, reason) do
    ObservabilityLogger.emit(:info, :orchestrator_blocked_resource_released, %{
      component: "orchestrator.blocked_resource_registry",
      issue_id: Map.get(record, "issue_id"),
      issue_identifier: Map.get(record, "issue_identifier"),
      run_id: Map.get(record, "run_id"),
      session_id: Map.get(record, "session_id"),
      resource_kind: kind,
      resource_id: id,
      blocker_code: Map.get(record, "blocker_code"),
      release_reason: reason_string(reason),
      result_summary: "orchestrator_resource_unblocked"
    })

    :ok
  end

  defp tracker_issue_id("tracker_issue", resource_id, _attrs), do: resource_id
  defp tracker_issue_id(_resource_kind, _resource_id, attrs), do: string_value(attrs, "issue_id") || string_value(attrs, :issue_id)

  defp string_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) -> normalize_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> value |> Atom.to_string() |> normalize_string()
      _value -> nil
    end
  end

  defp string_value(_map, _key), do: nil

  defp get_in_string(map, path) when is_map(map) and is_list(path) do
    case get_in(map, path) do
      value when is_binary(value) -> normalize_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) and not is_nil(value) -> value |> Atom.to_string() |> normalize_string()
      _value -> nil
    end
  end

  defp get_in_string(_map, _path), do: nil

  defp list_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      values when is_list(values) -> values
      nil -> nil
      value -> [value]
    end
  end

  defp list_value(_map, _key), do: nil

  defp reason_string(reason) when is_binary(reason), do: reason
  defp reason_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_string(reason), do: inspect(reason)

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
