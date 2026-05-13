defmodule SymphonyElixir.Repo.Git.Validation do
  @moduledoc false

  alias SymphonyElixir.Repo.Error

  @spec present(atom(), Path.t() | nil, term(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def present(operation, path, value, label) do
    case present_string(value) do
      nil -> {:error, Error.invalid_invocation(operation, "#{label} is required", path)}
      present -> {:ok, present}
    end
  end

  @spec directory(Path.t() | nil, atom()) :: :ok | {:error, Error.t()}
  def directory(path, operation) do
    case present_string(path) do
      nil -> :ok
      "." -> :ok
      repo_path -> if File.dir?(repo_path), do: :ok, else: {:error, Error.not_git_repo(operation, path, :path_missing)}
    end
  end

  @spec parent_directory(Path.t(), atom()) :: :ok | {:error, Error.t()}
  def parent_directory(path, operation) do
    parent = Path.dirname(path)

    if File.dir?(parent) do
      :ok
    else
      {:error, Error.not_git_repo(operation, parent, :parent_path_missing)}
    end
  end

  @spec blank_to_default(String.t(), String.t()) :: String.t()
  def blank_to_default("", default), do: default
  def blank_to_default(value, _default), do: value

  @spec present_string(term()) :: String.t() | nil
  def present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def present_string(_value), do: nil
end
