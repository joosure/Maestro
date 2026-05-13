defmodule SymphonyWorkerDaemon.WorkspaceManager.Paths do
  @moduledoc false

  alias SymphonyElixir.PathSafety

  @spec requested_cwd(term()) :: {:ok, Path.t()} | {:error, :workspace_cwd_missing}
  def requested_cwd(%{"cwd" => cwd}) when is_binary(cwd), do: non_empty_path(cwd)
  def requested_cwd(%{cwd: cwd}) when is_binary(cwd), do: non_empty_path(cwd)
  def requested_cwd(cwd) when is_binary(cwd), do: non_empty_path(cwd)
  def requested_cwd(_workspace_request), do: {:error, :workspace_cwd_missing}

  @spec canonicalize(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def canonicalize(path) when is_binary(path) do
    path
    |> Path.expand()
    |> PathSafety.canonicalize()
    |> case do
      {:ok, canonical_path} -> {:ok, canonical_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec canonical_roots(term()) :: {:ok, [Path.t()]} | {:error, term()}
  def canonical_roots([]), do: {:error, :workspace_roots_missing}

  def canonical_roots(roots) when is_list(roots) do
    roots
    |> Enum.reduce_while({:ok, []}, fn root, {:ok, acc} ->
      case root |> to_string() |> canonicalize() do
        {:ok, canonical_root} -> {:cont, {:ok, acc ++ [canonical_root]}}
        {:error, reason} -> {:halt, {:error, {:workspace_root_invalid, root, reason}}}
      end
    end)
  end

  def canonical_roots(_roots), do: {:error, :workspace_roots_invalid}

  @spec validate_under_allowed_root(Path.t(), [Path.t()]) :: :ok | {:error, term()}
  def validate_under_allowed_root(canonical_cwd, roots) do
    if Enum.any?(roots, &under_root?(canonical_cwd, &1)) do
      :ok
    else
      {:error, {:workspace_outside_allowed_roots, canonical_cwd, roots}}
    end
  end

  @spec validate_cleanup_target(Path.t(), [Path.t()]) :: :ok | {:error, term()}
  def validate_cleanup_target(canonical_workspace, roots) when is_binary(canonical_workspace) and is_list(roots) do
    if canonical_workspace in roots do
      {:error, {:workspace_cleanup_refuses_root, canonical_workspace}}
    else
      :ok
    end
  end

  defp non_empty_path(path) do
    case String.trim(path) do
      "" -> {:error, :workspace_cwd_missing}
      value -> {:ok, value}
    end
  end

  defp under_root?(path, root) when is_binary(path) and is_binary(root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end
