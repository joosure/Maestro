defmodule SymphonyElixir.Repo.Git.Remote do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Arguments, Command, Errors, References, Validation}

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec published_head_sha(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def published_head_sha(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts) do
    with :ok <- Validation.directory(path, :published_head_sha),
         {:ok, remote} <- Validation.present(:published_head_sha, path, remote, "remote"),
         {:ok, branch} <- Validation.present(:published_head_sha, path, branch, "branch") do
      ref = "refs/heads/#{branch}"
      display_ref = "#{remote}/#{branch}"

      case Command.run(path, ["ls-remote", remote, ref], opts) do
        {:ok, output} ->
          References.published_head_sha(output, path, display_ref)

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:published_head_sha, path)}

        {:error, {status, output}} ->
          {:error, Errors.published_head_sha(path, remote, display_ref, status, output)}
      end
    end
  end

  @spec remote_url(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_url(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts) do
    with :ok <- Validation.directory(path, :remote_url) do
      case Command.run(path, ["remote", "get-url", remote], opts) do
        {:ok, output} ->
          case Validation.present_string(output) do
            url when is_binary(url) -> {:ok, url}
            nil -> {:error, Error.remote_not_found(:remote_url, path, remote)}
          end

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:remote_url, path)}

        {:error, {status, output}} ->
          {:error, Errors.remote_url(path, remote, status, output)}
      end
    end
  end

  @spec remote_default_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def remote_default_branch(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts) do
    with :ok <- Validation.directory(path, :remote_default_branch) do
      case Command.run(path, ["symbolic-ref", "refs/remotes/#{remote}/HEAD"], opts) do
        {:ok, output} ->
          References.remote_default_branch(output, path, remote)

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:remote_default_branch, path)}

        {:error, {status, output}} ->
          {:error, Errors.remote(:remote_default_branch, path, remote, status, output)}
      end
    end
  end

  @spec remote_default_branch_from_url(String.t(), keyword()) :: result(String.t())
  def remote_default_branch_from_url(remote_url, opts \\ [])
      when is_binary(remote_url) and is_list(opts) do
    with {:ok, remote_url} <- Validation.present(:remote_default_branch_from_url, nil, remote_url, "remote URL") do
      case Command.run(nil, ["ls-remote", "--symref", remote_url, "HEAD"], opts) do
        {:ok, output} ->
          References.ls_remote_default_branch(output, remote_url)

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:remote_default_branch_from_url)}

        {:error, {status, output}} ->
          {:error,
           Errors.remote_operation(
             :remote_default_branch_from_url,
             nil,
             remote_url,
             :remote_default_branch_lookup_failed,
             status,
             output
           )}
      end
    end
  end

  @spec fetch(Path.t(), String.t(), keyword()) :: result(String.t())
  def fetch(path \\ ".", remote \\ "origin", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_list(opts) do
    with :ok <- Validation.directory(path, :fetch),
         {:ok, remote} <- Validation.present(:fetch, path, remote, "remote") do
      case Command.run(path, ["fetch", remote], opts) do
        {:ok, output} -> {:ok, String.trim(output)}
        {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(:fetch, path)}
        {:error, {status, output}} -> {:error, Errors.remote_operation(:fetch, path, remote, :fetch_failed, status, output)}
      end
    end
  end

  @spec clone(String.t(), Path.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, opts \\ []) when is_binary(remote_url) and is_binary(target_path) and is_list(opts) do
    branch = Keyword.get(opts, :branch)

    case branch do
      branch when is_binary(branch) -> clone(remote_url, target_path, branch, opts)
      _other -> do_clone(remote_url, target_path, nil, opts)
    end
  end

  @spec clone(String.t(), Path.t(), String.t(), keyword()) :: result(String.t())
  def clone(remote_url, target_path, branch, opts)
      when is_binary(remote_url) and is_binary(target_path) and is_binary(branch) and is_list(opts) do
    do_clone(remote_url, target_path, branch, opts)
  end

  @spec push(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def push(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts) do
    with :ok <- Validation.directory(path, :push),
         {:ok, remote} <- Validation.present(:push, path, remote, "remote"),
         {:ok, branch} <- Validation.present(:push, path, branch, "branch") do
      args =
        ["push"]
        |> Arguments.append_force_with_lease(Keyword.get(opts, :force_with_lease, false))
        |> Arguments.append_set_upstream(Keyword.get(opts, :set_upstream, false))
        |> Kernel.++([remote, branch])

      case Command.run(path, args, opts) do
        {:ok, output} ->
          {:ok, String.trim(output)}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:push, path)}

        {:error, {status, output}} ->
          {:error, Errors.push(path, remote, branch, status, output)}
      end
    end
  end

  @spec delete_remote_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def delete_remote_branch(path, remote, branch, opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(branch) and is_list(opts) do
    with :ok <- Validation.directory(path, :delete_remote_branch),
         {:ok, remote} <- Validation.present(:delete_remote_branch, path, remote, "remote"),
         {:ok, branch} <- Validation.present(:delete_remote_branch, path, branch, "branch") do
      case Command.run(path, ["push", remote, "--delete", branch], opts) do
        {:ok, output} ->
          {:ok, String.trim(output)}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:delete_remote_branch, path)}

        {:error, {status, output}} ->
          {:error, Errors.delete_remote_branch(path, remote, branch, status, output)}
      end
    end
  end

  defp do_clone(remote_url, target_path, branch, opts) do
    with {:ok, remote_url} <- Validation.present(:clone, nil, remote_url, "remote URL"),
         {:ok, target_path} <- Validation.present(:clone, nil, target_path, "target path"),
         :ok <- Validation.parent_directory(target_path, :clone) do
      args =
        ["clone"]
        |> Arguments.append_depth(Keyword.get(opts, :depth))
        |> Arguments.append_branch(branch)
        |> Kernel.++([remote_url, target_path])

      case Command.run(nil, args, opts) do
        {:ok, output} -> {:ok, String.trim(output)}
        {:error, {:enoent, _output}} -> {:error, Error.missing_tooling(:clone)}
        {:error, {status, output}} -> {:error, Errors.remote_operation(:clone, target_path, remote_url, :clone_failed, status, output)}
      end
    end
  end
end
