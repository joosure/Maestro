defmodule SymphonyElixir.Repo.Error do
  @moduledoc """
  Structured error type for provider-neutral repository operations.

  Repo errors describe local Git/repository failures only. Code-host concerns
  such as pull requests, checks, auth, or reviews belong to
  `SymphonyElixir.RepoProvider.Error`.
  """

  @enforce_keys [:operation, :code]
  defstruct [:operation, :code, :message, :path, details: %{}, exit_code: 1, retryable?: false]

  @type t :: %__MODULE__{
          operation: atom(),
          code: atom(),
          message: String.t() | nil,
          path: Path.t() | nil,
          details: map(),
          exit_code: non_neg_integer(),
          retryable?: boolean()
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, %{
      operation: Map.fetch!(attrs, :operation),
      code: Map.fetch!(attrs, :code),
      message: Map.get(attrs, :message),
      path: Map.get(attrs, :path),
      details: Map.get(attrs, :details, %{}),
      exit_code: Map.get(attrs, :exit_code, 1),
      retryable?: Map.get(attrs, :retryable?, false)
    })
  end

  @spec missing_tooling(atom(), Path.t() | nil) :: t()
  def missing_tooling(operation, path \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :missing_tooling,
      message: "Repo operations require git in PATH",
      path: path,
      exit_code: 64
    })
  end

  @spec not_git_repo(atom(), Path.t() | nil, term()) :: t()
  def not_git_repo(operation, path, details \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :not_git_repo,
      message: "Path is not a Git worktree",
      path: path,
      details: details_map(details),
      exit_code: 64
    })
  end

  @spec detached_head(atom(), Path.t() | nil) :: t()
  def detached_head(operation, path \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :detached_head,
      message: "Git HEAD is detached",
      path: path
    })
  end

  @spec head_unavailable(atom(), Path.t() | nil, term()) :: t()
  def head_unavailable(operation, path, details \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :head_unavailable,
      message: "Git HEAD is unavailable",
      path: path,
      details: details_map(details)
    })
  end

  @spec remote_not_found(atom(), Path.t() | nil, String.t(), term()) :: t()
  def remote_not_found(operation, path, remote, details \\ nil)
      when is_atom(operation) and is_binary(remote) do
    new(%{
      operation: operation,
      code: :remote_not_found,
      message: "Git remote #{inspect(remote)} was not found",
      path: path,
      details: Map.put(details_map(details), :remote, remote),
      exit_code: 64
    })
  end

  @spec auth_failed(atom(), Path.t() | nil, term()) :: t()
  def auth_failed(operation, path \\ nil, details \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :auth_failed,
      message: "Git remote authentication failed",
      path: path,
      details: details_map(details)
    })
  end

  @spec remote_unavailable(atom(), Path.t() | nil, String.t(), term()) :: t()
  def remote_unavailable(operation, path, remote, details \\ nil)
      when is_atom(operation) and is_binary(remote) do
    new(%{
      operation: operation,
      code: :remote_unavailable,
      message: "Git remote #{inspect(remote)} is unavailable",
      path: path,
      details: Map.put(details_map(details), :remote, remote),
      retryable?: true
    })
  end

  @spec git_command_failed(atom(), Path.t() | nil, non_neg_integer() | atom(), String.t()) :: t()
  def git_command_failed(operation, path, status, output)
      when is_atom(operation) and (is_integer(status) or is_atom(status)) and is_binary(output) do
    operation_failed(operation, :git_command_failed, path, status, output)
  end

  @spec operation_failed(atom(), atom(), Path.t() | nil, non_neg_integer() | atom(), String.t()) :: t()
  def operation_failed(operation, code, path, status, output)
      when is_atom(operation) and is_atom(code) and (is_integer(status) or is_atom(status)) and is_binary(output) do
    new(%{
      operation: operation,
      code: code,
      message: output |> String.trim() |> blank_to_default("Git command failed"),
      path: path,
      details: %{status: status, output: output}
    })
  end

  @spec invalid_invocation(atom(), String.t(), Path.t() | nil, term()) :: t()
  def invalid_invocation(operation, message, path \\ nil, details \\ nil)
      when is_atom(operation) and is_binary(message) do
    new(%{
      operation: operation,
      code: :invalid_invocation,
      message: message,
      path: path,
      details: details_map(details),
      exit_code: 64
    })
  end

  @spec dirty_worktree(atom(), Path.t() | nil, term()) :: t()
  def dirty_worktree(operation, path, details \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :dirty_worktree,
      message: "Git working tree has local changes",
      path: path,
      details: details_map(details)
    })
  end

  @spec conflict(atom(), Path.t() | nil, term()) :: t()
  def conflict(operation, path, details \\ nil) when is_atom(operation) do
    new(%{
      operation: operation,
      code: :conflict,
      message: "Git working tree has unresolved conflicts",
      path: path,
      details: details_map(details)
    })
  end

  @spec branch_exists(atom(), Path.t() | nil, String.t(), term()) :: t()
  def branch_exists(operation, path, branch, details \\ nil)
      when is_atom(operation) and is_binary(branch) do
    new(%{
      operation: operation,
      code: :branch_exists,
      message: "Git branch #{inspect(branch)} already exists",
      path: path,
      details: Map.put(details_map(details), :branch, branch),
      exit_code: 64
    })
  end

  @spec branch_not_found(atom(), Path.t() | nil, String.t(), term()) :: t()
  def branch_not_found(operation, path, branch, details \\ nil)
      when is_atom(operation) and is_binary(branch) do
    new(%{
      operation: operation,
      code: :branch_not_found,
      message: "Git branch or ref #{inspect(branch)} was not found",
      path: path,
      details: Map.put(details_map(details), :branch, branch),
      exit_code: 64
    })
  end

  @spec branch_diverged(atom(), Path.t() | nil, String.t(), term()) :: t()
  def branch_diverged(operation, path, branch, details \\ nil)
      when is_atom(operation) and is_binary(branch) do
    new(%{
      operation: operation,
      code: :branch_diverged,
      message: "Git branch or ref #{inspect(branch)} cannot be fast-forwarded",
      path: path,
      details: Map.put(details_map(details), :branch, branch)
    })
  end

  @spec push_rejected(Path.t() | nil, String.t(), String.t(), term()) :: t()
  def push_rejected(path, remote, branch, details \\ nil)
      when is_binary(remote) and is_binary(branch) do
    new(%{
      operation: :push,
      code: :push_rejected,
      message: "Git push to #{remote}/#{branch} was rejected",
      path: path,
      details:
        details
        |> details_map()
        |> Map.merge(%{remote: remote, branch: branch})
    })
  end

  defp details_map(nil), do: %{}
  defp details_map(details) when is_map(details), do: details
  defp details_map(details), do: %{source_reason: details}

  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value
end
