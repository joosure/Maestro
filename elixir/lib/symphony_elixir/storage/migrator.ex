defmodule SymphonyElixir.Storage.Migrator do
  @moduledoc """
  Synchronous local storage migration runner.

  The local SQLite backend is intended for single-node durable storage. Running
  migrations before durable stores start keeps restart recovery deterministic
  for the local service profile.
  """

  alias SymphonyElixir.Platform.PrivAssets
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
    path = migrations_path(repo)
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

  defp migrations_path(repo) do
    repo
    |> repo_priv_root()
    |> Path.join("migrations")
    |> PrivAssets.app_priv_root!(otp_app: repo_otp_app(repo))
  end

  defp repo_priv_root(repo) do
    repo
    |> repo_config()
    |> Keyword.get(:priv, "priv/storage_repo")
    |> strip_priv_prefix()
  end

  defp repo_otp_app(repo) do
    repo
    |> repo_config()
    |> Keyword.get(:otp_app, :symphony_elixir)
  end

  defp repo_config(repo) do
    if function_exported?(repo, :config, 0) do
      repo.config()
    else
      []
    end
  end

  defp strip_priv_prefix("priv/" <> rest), do: rest
  defp strip_priv_prefix("priv"), do: ""
  defp strip_priv_prefix(priv) when is_binary(priv), do: priv
end
