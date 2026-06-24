defmodule SymphonyElixir.Storage.Migrator do
  @moduledoc """
  Synchronous local storage migration runner.

  The local SQLite backend is intended for single-node durable storage. Running
  migrations before durable stores start keeps restart recovery deterministic
  for the local service profile.
  """

  alias SymphonyElixir.Storage.{ErrorCodes, Repo}

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient
    }
  end

  @spec start_link(keyword()) :: :ignore | {:error, term()}
  def start_link(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case migrate(repo) do
      :ok -> :ignore
      {:error, reason} -> {:error, reason}
    end
  end

  @spec migrate(module()) :: :ok | {:error, map()}
  def migrate(repo \\ Repo) do
    path = Ecto.Migrator.migrations_path(repo)
    compiler_options = Code.compiler_options()

    try do
      Code.compiler_options(ignore_module_conflict: true)
      Ecto.Migrator.run(repo, path, :up, all: true)
      :ok
    rescue
      error -> {:error, migration_error(error)}
    catch
      kind, reason -> {:error, migration_error({kind, reason})}
    after
      Code.compiler_options(ignore_module_conflict: Map.get(compiler_options, :ignore_module_conflict, false))
    end
  end

  defp migration_error(reason) do
    %{
      code: ErrorCodes.migration_failed(),
      message: "Storage migrations failed.",
      reason: reason
    }
  end
end
