defmodule SymphonyElixir.Repo.Git.Inspection do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Command, Errors, StatusParser, Validation}
  alias SymphonyElixir.Repo.Status

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec root(Path.t(), keyword()) :: result(Path.t())
  def root(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    with :ok <- Validation.directory(path, :root) do
      case Command.run(path, ["rev-parse", "--show-toplevel"], opts) do
        {:ok, output} ->
          {:ok, String.trim(output)}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:root, path)}

        {:error, {status, output}} ->
          {:error, Errors.git(:root, path, status, output)}
      end
    end
  end

  @spec current_branch(Path.t(), keyword()) :: result(String.t())
  def current_branch(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    with :ok <- Validation.directory(path, :current_branch) do
      case Command.run(path, ["branch", "--show-current"], opts) do
        {:ok, output} ->
          case Validation.present_string(output) do
            branch when is_binary(branch) -> {:ok, branch}
            nil -> {:error, Error.detached_head(:current_branch, path)}
          end

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:current_branch, path)}

        {:error, {status, output}} ->
          {:error, Errors.git(:current_branch, path, status, output)}
      end
    end
  end

  @spec head_sha(Path.t(), keyword()) :: result(String.t())
  def head_sha(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    with :ok <- Validation.directory(path, :head_sha) do
      case Command.run(path, ["rev-parse", "HEAD"], opts) do
        {:ok, output} ->
          case Validation.present_string(output) do
            sha when is_binary(sha) -> {:ok, sha}
            nil -> {:error, Error.head_unavailable(:head_sha, path)}
          end

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:head_sha, path)}

        {:error, {status, output}} ->
          {:error, Errors.git(:head_sha, path, status, output)}
      end
    end
  end

  @spec status(Path.t(), keyword()) :: result(Status.t())
  def status(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    case root(path, opts) do
      {:ok, repo_root} ->
        with {:ok, entries} <- status_entries(repo_root, opts) do
          {:ok,
           Status.new(%{
             path: path,
             root: repo_root,
             branch: optional_branch(repo_root, opts),
             head_sha: optional_head_sha(repo_root, opts),
             entries: entries,
             detached?: detached?(repo_root, opts)
           })}
        end

      {:error, %Error{code: :not_git_repo} = error} ->
        {:ok, Status.missing(path, error)}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec diff(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff(path \\ ".", args \\ [], opts \\ [])
      when is_binary(path) and is_list(args) and is_list(opts) do
    with :ok <- Validation.directory(path, :diff) do
      case Command.run(path, ["diff" | args], opts) do
        {:ok, output} -> {:ok, String.trim_trailing(output)}
        {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(:diff, path)}
        {:error, {status, output}} -> {:error, Error.operation_failed(:diff, :diff_failed, path, status, output)}
      end
    end
  end

  @spec diff_check(Path.t(), keyword()) :: result(String.t())
  def diff_check(path \\ ".", opts \\ []) when is_binary(path) and is_list(opts) do
    diff_check(path, [], opts)
  end

  @spec diff_check(Path.t(), [String.t()], keyword()) :: result(String.t())
  def diff_check(path, args, opts) when is_binary(path) and is_list(args) and is_list(opts) do
    with :ok <- Validation.directory(path, :diff_check) do
      case Command.run(path, ["diff", "--check" | args], opts) do
        {:ok, ""} -> {:ok, "ok"}
        {:ok, output} -> {:ok, output |> String.trim() |> Validation.blank_to_default("ok")}
        {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(:diff_check, path)}
        {:error, {status, output}} -> {:error, Error.operation_failed(:diff_check, :diff_check_failed, path, status, output)}
      end
    end
  end

  defp status_entries(path, opts) do
    case Command.run(path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], opts) do
      {:ok, output} -> {:ok, StatusParser.parse(output)}
      {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(:status, path)}
      {:error, {status, output}} -> {:error, Errors.git(:status, path, status, output)}
    end
  end

  defp optional_branch(path, opts) do
    case current_branch(path, opts) do
      {:ok, branch} -> branch
      {:error, _error} -> nil
    end
  end

  defp optional_head_sha(path, opts) do
    case head_sha(path, opts) do
      {:ok, sha} -> sha
      {:error, _error} -> nil
    end
  end

  defp detached?(path, opts) do
    case current_branch(path, opts) do
      {:ok, _branch} -> false
      {:error, %Error{code: :detached_head}} -> true
      {:error, _error} -> false
    end
  end
end
