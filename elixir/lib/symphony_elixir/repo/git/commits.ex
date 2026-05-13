defmodule SymphonyElixir.Repo.Git.Commits do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Command, Inspection, Output, Validation}
  alias SymphonyElixir.Repo.Status

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec enable_rerere(Path.t(), keyword()) :: result(String.t())
  def enable_rerere(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    with :ok <- Validation.directory(path, :enable_rerere),
         {:ok, enabled_output} <- set_config(path, "rerere.enabled", "true", :enable_rerere, opts),
         {:ok, autoupdate_output} <- set_config(path, "rerere.autoupdate", "true", :enable_rerere, opts) do
      {:ok, Output.joined([enabled_output, autoupdate_output], "rerere enabled")}
    end
  end

  @spec stage_all(Path.t(), keyword()) :: result(String.t())
  def stage_all(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    with :ok <- Validation.directory(path, :stage_all),
         {:ok, output} <- add_all(path, opts, :stage_all) do
      {:ok, output |> String.trim() |> Validation.blank_to_default("staged")}
    end
  end

  @spec commit_all(Path.t(), String.t(), keyword()) :: result(String.t() | :noop)
  def commit_all(path, message, opts \\ [])
      when is_binary(path) and is_binary(message) and is_list(opts) do
    plain_opts = Keyword.delete(opts, :git_config)

    with :ok <- Validation.directory(path, :commit_all),
         {:ok, message} <- Validation.present(:commit_all, path, message, "commit message"),
         {:ok, repo_status} <- Inspection.status(path, plain_opts),
         :ok <- validate_committable_status(path, repo_status),
         {:ok, add_output} <- add_all(path, plain_opts),
         {:ok, commit_output} <- commit(path, message, opts) do
      case Inspection.head_sha(path, plain_opts) do
        {:ok, sha} -> {:ok, sha}
        {:error, _error} -> {:ok, String.trim(commit_output <> add_output)}
      end
    end
  end

  @spec commit_staged(Path.t(), String.t(), keyword()) :: result(String.t())
  def commit_staged(path, message, opts \\ [])
      when is_binary(path) and is_binary(message) and is_list(opts) do
    plain_opts = Keyword.delete(opts, :git_config)

    with :ok <- Validation.directory(path, :commit_staged),
         {:ok, message} <- Validation.present(:commit_staged, path, message, "commit message"),
         {:ok, commit_output} <- commit(path, message, :commit_staged, opts) do
      case Inspection.head_sha(path, plain_opts) do
        {:ok, sha} -> {:ok, sha}
        {:error, _error} -> {:ok, String.trim(commit_output)}
      end
    end
  end

  defp add_all(path, opts, operation \\ :commit_all) do
    case Command.run(path, ["add", "-A"], opts) do
      {:ok, output} -> {:ok, output}
      {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(operation, path)}
      {:error, {status, output}} -> {:error, Error.operation_failed(operation, :add_failed, path, status, output)}
    end
  end

  defp commit(path, message, opts), do: commit(path, message, :commit_all, opts)

  defp commit(path, message, operation, opts) do
    case Command.run(path, ["commit", "-m", message], opts) do
      {:ok, output} -> {:ok, output}
      {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(operation, path)}
      {:error, {status, output}} -> {:error, Error.operation_failed(operation, :commit_failed, path, status, output)}
    end
  end

  defp set_config(path, key, value, operation, opts) do
    case Command.run(path, ["config", "--local", key, value], opts) do
      {:ok, output} -> {:ok, output}
      {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(operation, path)}
      {:error, {status, output}} -> {:error, Error.operation_failed(operation, :config_failed, path, status, output)}
    end
  end

  defp validate_committable_status(_path, %Status{missing?: true, error: %Error{} = error}), do: {:error, error}
  defp validate_committable_status(_path, %Status{clean?: true}), do: {:ok, :noop}

  defp validate_committable_status(path, %Status{conflicted?: true} = repo_status),
    do: {:error, Error.conflict(:commit_all, path, %{status: repo_status})}

  defp validate_committable_status(_path, %Status{}), do: :ok
end
