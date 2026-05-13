defmodule SymphonyElixir.Agent.Credential.Store.Paths do
  @moduledoc false

  @metadata_file "metadata.json"
  @state_file "state.json"
  @rotation_file "rotation.json"
  @usage_periods_file "usage_periods.csv"

  @spec metadata_path(Path.t()) :: Path.t()
  def metadata_path(account_dir), do: Path.join(account_dir, @metadata_file)

  @spec state_path(Path.t()) :: Path.t()
  def state_path(account_dir), do: Path.join(account_dir, @state_file)

  @spec usage_periods_csv_path(map() | nil) :: Path.t() | nil
  def usage_periods_csv_path(%{account_dir: account_dir}) when is_binary(account_dir),
    do: Path.join(account_dir, @usage_periods_file)

  def usage_periods_csv_path(_account), do: nil

  @spec backend_dir(String.t(), map()) :: Path.t()
  def backend_dir(provider_kind, settings),
    do: Path.join(settings.store_root, safe_segment(provider_kind))

  @spec account_dir(String.t(), String.t(), map()) :: Path.t()
  def account_dir(provider_kind, id, settings),
    do: Path.join(backend_dir(provider_kind, settings), safe_segment(id))

  @spec rotation_path(String.t(), map()) :: Path.t()
  def rotation_path(provider_kind, settings),
    do: Path.join(backend_dir(provider_kind, settings), @rotation_file)

  @spec account_dirs(Path.t()) :: [Path.t()]
  def account_dirs(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries |> Enum.map(&Path.join(path, &1)) |> Enum.filter(&File.dir?/1)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise File.Error, action: "list agent credential directory", path: path, reason: reason
    end
  end

  @spec safe_segment(String.t()) :: String.t()
  def safe_segment(value) do
    value
    |> URI.encode(&(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in ~c"-_.@"))
    |> String.replace("%", "_")
  end
end
