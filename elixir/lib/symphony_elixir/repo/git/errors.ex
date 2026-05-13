defmodule SymphonyElixir.Repo.Git.Errors do
  @moduledoc false

  alias SymphonyElixir.Repo.Error

  @type exit_status :: non_neg_integer() | atom()

  @spec remote_url(Path.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def remote_url(path, remote, status, output), do: remote(:remote_url, path, remote, status, output)

  @spec remote(atom(), Path.t() | nil, String.t(), exit_status(), String.t()) :: Error.t()
  def remote(operation, path, remote, status, output) do
    if status in [2, 128] do
      Error.remote_not_found(operation, path, remote, %{status: status, output: output})
    else
      git(operation, path, status, output)
    end
  end

  @spec push(Path.t(), String.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def push(path, remote, branch, status, output) do
    cond do
      auth_failed_output?(output) ->
        Error.auth_failed(:push, path, %{status: status, output: output, remote: remote, branch: branch})

      remote_unavailable_output?(output) ->
        Error.remote_unavailable(:push, path, remote, %{status: status, output: output, branch: branch})

      push_rejected_output?(output) ->
        Error.push_rejected(path, remote, branch, %{status: status, output: output})

      true ->
        Error.operation_failed(:push, :push_failed, path, status, output)
    end
  end

  @spec delete_remote_branch(Path.t(), String.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def delete_remote_branch(path, remote, branch, status, output) do
    cond do
      auth_failed_output?(output) ->
        Error.auth_failed(:delete_remote_branch, path, %{status: status, output: output, remote: remote, branch: branch})

      remote_unavailable_output?(output) ->
        Error.remote_unavailable(:delete_remote_branch, path, remote, %{status: status, output: output, branch: branch})

      branch_already_deleted_output?(output) ->
        Error.branch_not_found(:delete_remote_branch, path, branch, %{status: status, output: output})

      true ->
        Error.operation_failed(:delete_remote_branch, :delete_remote_branch_failed, path, status, output)
    end
  end

  @spec create_branch(Path.t(), String.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def create_branch(path, branch, base_ref, status, output) do
    cond do
      branch_exists_output?(output) ->
        Error.branch_exists(:create_branch, path, branch, %{status: status, output: output})

      ref_not_found_output?(output) ->
        Error.branch_not_found(:create_branch, path, base_ref, %{status: status, output: output})

      true ->
        Error.operation_failed(:create_branch, :branch_create_failed, path, status, output)
    end
  end

  @spec switch_branch(Path.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def switch_branch(path, branch, status, output) do
    cond do
      ref_not_found_output?(output) ->
        Error.branch_not_found(:switch_branch, path, branch, %{status: status, output: output})

      dirty_worktree_output?(output) ->
        Error.dirty_worktree(:switch_branch, path, %{status: status, output: output})

      true ->
        Error.operation_failed(:switch_branch, :branch_switch_failed, path, status, output)
    end
  end

  @spec merge(Path.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def merge(path, ref, status, output) do
    cond do
      conflict_output?(output) ->
        Error.conflict(:merge, path, %{status: status, output: output, ref: ref})

      dirty_worktree_output?(output) ->
        Error.dirty_worktree(:merge, path, %{status: status, output: output, ref: ref})

      ref_not_found_output?(output) ->
        Error.branch_not_found(:merge, path, ref, %{status: status, output: output})

      non_fast_forward_output?(output) ->
        Error.branch_diverged(:merge, path, ref, %{status: status, output: output})

      true ->
        Error.operation_failed(:merge, :merge_failed, path, status, output)
    end
  end

  @spec published_head_sha(Path.t(), String.t(), String.t(), exit_status(), String.t()) :: Error.t()
  def published_head_sha(path, remote, ref, status, output) do
    cond do
      auth_failed_output?(output) ->
        Error.auth_failed(:published_head_sha, path, %{status: status, output: output, remote: remote, ref: ref})

      remote_unavailable_output?(output) ->
        Error.remote_unavailable(:published_head_sha, path, remote, %{status: status, output: output, ref: ref})

      ref_not_found_output?(output) ->
        Error.branch_not_found(:published_head_sha, path, ref, %{status: status, output: output})

      true ->
        Error.operation_failed(:published_head_sha, :published_head_unavailable, path, status, output)
    end
  end

  @spec remote_operation(atom(), Path.t() | nil, String.t(), atom(), exit_status(), String.t()) :: Error.t()
  def remote_operation(operation, path, remote, error_code, status, output) do
    cond do
      auth_failed_output?(output) ->
        Error.auth_failed(operation, path, %{status: status, output: output, remote: remote})

      remote_unavailable_output?(output) ->
        Error.remote_unavailable(operation, path, remote, %{status: status, output: output})

      true ->
        Error.operation_failed(operation, error_code, path, status, output)
    end
  end

  @spec git(atom(), Path.t() | nil, exit_status(), String.t()) :: Error.t()
  def git(operation, path, status, output) do
    if not_git_repo_output?(output) do
      Error.not_git_repo(operation, path, %{status: status, output: output})
    else
      Error.git_command_failed(operation, path, status, output)
    end
  end

  defp not_git_repo_output?(output) when is_binary(output) do
    normalized = String.downcase(output)
    String.contains?(normalized, "not a git repository") or String.contains?(normalized, "not a git work tree")
  end

  defp push_rejected_output?(output) when is_binary(output) do
    normalized = String.downcase(output)
    String.contains?(normalized, "rejected") or String.contains?(normalized, "non-fast-forward")
  end

  defp auth_failed_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "authentication failed") or
      String.contains?(normalized, "could not read username") or
      String.contains?(normalized, "permission denied") or
      String.contains?(normalized, "access denied") or
      String.contains?(normalized, "not authorized") or
      String.contains?(normalized, "authorization failed") or
      String.contains?(normalized, "invalid username or password")
  end

  defp remote_unavailable_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "could not resolve host") or
      String.contains?(normalized, "failed to connect") or
      String.contains?(normalized, "connection timed out") or
      String.contains?(normalized, "network is unreachable") or
      String.contains?(normalized, "couldn't connect to server") or
      String.contains?(normalized, "could not read from remote repository") or
      String.contains?(normalized, "does not appear to be a git repository") or
      String.contains?(normalized, "repository not found")
  end

  defp non_fast_forward_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "not possible to fast-forward") or
      String.contains?(normalized, "non-fast-forward")
  end

  defp branch_exists_output?(output) when is_binary(output) do
    normalized = String.downcase(output)
    String.contains?(normalized, "already exists")
  end

  defp ref_not_found_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "invalid reference") or
      String.contains?(normalized, "did not match") or
      String.contains?(normalized, "unknown revision") or
      String.contains?(normalized, "not a valid") or
      String.contains?(normalized, "not found")
  end

  defp dirty_worktree_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "local changes") or
      String.contains?(normalized, "would be overwritten")
  end

  defp conflict_output?(output) when is_binary(output) do
    normalized = String.downcase(output)

    String.contains?(normalized, "conflict") or
      String.contains?(normalized, "automatic merge failed")
  end

  defp branch_already_deleted_output?(output) when is_binary(output) do
    normalized = String.downcase(output)
    String.contains?(normalized, "remote ref does not exist") or String.contains?(normalized, "remote branch not found")
  end
end
