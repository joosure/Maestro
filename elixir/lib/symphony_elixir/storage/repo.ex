defmodule SymphonyElixir.Storage.Repo do
  @moduledoc """
  Ecto repository for local durable Symphony storage.

  Domain stores remain behind their own storage behaviours. This Repo only
  provides the SQL boundary for adapters such as the Agent execution-plan
  SQLite backend.
  """

  use Ecto.Repo,
    otp_app: :symphony_elixir,
    adapter: Ecto.Adapters.SQLite3

  @sqlite_memory_database ":memory:"
  @sqlite_memory_database_uri_prefix "file::memory:"

  @impl true
  def init(_type, config) do
    config
    |> Keyword.get(:database)
    |> ensure_parent_dir!()

    {:ok, config}
  end

  defp ensure_parent_dir!(database) when is_binary(database) do
    unless memory_database?(database) do
      database
      |> Path.dirname()
      |> File.mkdir_p!()
    end
  end

  defp ensure_parent_dir!(_database), do: :ok

  defp memory_database?(@sqlite_memory_database), do: true

  defp memory_database?(database) when is_binary(database) do
    String.starts_with?(database, @sqlite_memory_database_uri_prefix)
  end
end
