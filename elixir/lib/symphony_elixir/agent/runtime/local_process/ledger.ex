defmodule SymphonyElixir.Agent.Runtime.LocalProcess.Ledger do
  @moduledoc false

  @record_version 1
  @default_root_name "symphony-elixir-local-processes"

  @type record :: map()

  @spec default_root() :: Path.t()
  def default_root do
    case Application.get_env(:symphony_elixir, :local_process_ledger_root) do
      root when is_binary(root) and root != "" -> Path.expand(root)
      _root -> Path.join(System.tmp_dir!(), @default_root_name)
    end
  end

  @spec root(keyword()) :: Path.t()
  def root(opts) when is_list(opts) do
    case Keyword.get(opts, :ledger_root) do
      root when is_binary(root) and root != "" -> Path.expand(root)
      _root -> default_root()
    end
  end

  @spec new_id() :: String.t()
  def new_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec build_record(String.t(), pos_integer(), map()) :: record()
  def build_record(id, os_pid, attrs) when is_binary(id) and is_integer(os_pid) and os_pid > 0 and is_map(attrs) do
    attrs
    |> stringify_keys()
    |> Map.merge(%{
      "id" => id,
      "version" => @record_version,
      "os_pid" => os_pid,
      "owner_os_pid" => owner_os_pid(),
      "registered_at_unix_ms" => System.system_time(:millisecond)
    })
    |> compact_nil_values()
  end

  @spec write_record(Path.t(), record()) :: :ok | {:error, term()}
  def write_record(root, %{"id" => id} = record) when is_binary(root) and is_binary(id) do
    with :ok <- File.mkdir_p(root),
         {:ok, json} <- Jason.encode(record),
         path <- record_path(root, id),
         tmp_path <- path <> ".tmp",
         :ok <- File.write(tmp_path, json),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_record(Path.t(), String.t() | nil) :: :ok
  def delete_record(_root, nil), do: :ok

  def delete_record(root, id) when is_binary(root) and is_binary(id) do
    root
    |> record_path(id)
    |> File.rm()
    |> case do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @spec list_records(Path.t()) :: [record()]
  def list_records(root) when is_binary(root) do
    root
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(&read_record/1)
  end

  @spec record_path(Path.t(), String.t()) :: Path.t()
  def record_path(root, id) when is_binary(root) and is_binary(id) do
    Path.join(root, sanitize_id(id) <> ".json")
  end

  @spec owner_os_pid() :: pos_integer() | nil
  def owner_os_pid do
    case Integer.parse(System.pid()) do
      {pid, ""} when pid > 0 -> pid
      _other -> nil
    end
  end

  defp read_record(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, record} when is_map(record) <- Jason.decode(contents) do
      [Map.put_new(record, "ledger_path", path)]
    else
      _error -> []
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), stringify_value(value))
    end)
  end

  defp stringify_value(%_{} = struct), do: struct |> Map.from_struct() |> stringify_keys()
  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp sanitize_id(id) do
    String.replace(id, ~r/[^A-Za-z0-9_-]/, "_")
  end
end
