defmodule SymphonyElixir.Repo.Git.Branches do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Git.{Command, Errors, Output, Remote, Validation}

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @spec merge(Path.t(), String.t(), keyword()) :: result(String.t())
  def merge(path, ref, opts \\ [])
      when is_binary(path) and is_binary(ref) and is_list(opts) do
    with :ok <- Validation.directory(path, :merge),
         {:ok, ref} <- Validation.present(:merge, path, ref, "merge ref") do
      args = if Keyword.get(opts, :ff_only, false), do: ["merge", "--ff-only", ref], else: ["merge", ref]

      case Command.run(path, args, opts) do
        {:ok, output} ->
          {:ok, String.trim(output)}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:merge, path)}

        {:error, {status, output}} ->
          {:error, Errors.merge(path, ref, status, output)}
      end
    end
  end

  @spec sync_base(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def sync_base(path \\ ".", remote \\ "origin", base_branch \\ "main", opts \\ [])
      when is_binary(path) and is_binary(remote) and is_binary(base_branch) and is_list(opts) do
    with :ok <- Validation.directory(path, :sync_base),
         {:ok, remote} <- Validation.present(:sync_base, path, remote, "remote"),
         {:ok, base_branch} <- Validation.present(:sync_base, path, base_branch, "base branch"),
         {:ok, fetch_output} <- Remote.fetch(path, remote, opts),
         {:ok, merge_output} <- merge(path, "#{remote}/#{base_branch}", opts) do
      {:ok, Output.joined([fetch_output, merge_output])}
    end
  end

  @spec create_branch(Path.t(), String.t(), String.t(), keyword()) :: result(String.t())
  def create_branch(path, branch, base_ref \\ "HEAD", opts \\ [])
      when is_binary(path) and is_binary(branch) and is_binary(base_ref) and is_list(opts) do
    with :ok <- Validation.directory(path, :create_branch),
         {:ok, branch} <- Validation.present(:create_branch, path, branch, "branch"),
         {:ok, base_ref} <- Validation.present(:create_branch, path, base_ref, "base ref") do
      case Command.run(path, ["switch", "-c", branch, base_ref], opts) do
        {:ok, _output} ->
          {:ok, branch}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:create_branch, path)}

        {:error, {status, output}} ->
          {:error, Errors.create_branch(path, branch, base_ref, status, output)}
      end
    end
  end

  @spec switch_branch(Path.t(), String.t(), keyword()) :: result(String.t())
  def switch_branch(path, branch, opts \\ [])
      when is_binary(path) and is_binary(branch) and is_list(opts) do
    with :ok <- Validation.directory(path, :switch_branch),
         {:ok, branch} <- Validation.present(:switch_branch, path, branch, "branch") do
      case Command.run(path, ["switch", branch], opts) do
        {:ok, _output} ->
          {:ok, branch}

        {:error, {:enoent, _output}} ->
          {:error, Error.missing_tooling(:switch_branch, path)}

        {:error, {status, output}} ->
          {:error, Errors.switch_branch(path, branch, status, output)}
      end
    end
  end
end
