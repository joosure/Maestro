defmodule SymphonyWorkerDaemon.Config.WorkspaceRoots do
  @moduledoc false

  alias SymphonyWorkerDaemon.Config.Options

  @spec resolve(keyword(), map()) :: {:ok, [String.t()]} | {:error, String.t()}
  def resolve(opts, deps) when is_list(opts) and is_map(deps) do
    roots =
      opts
      |> Keyword.get_values(:workspace_root)
      |> Enum.map(&Options.normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)

    case roots do
      [] -> {:error, "At least one --workspace-root is required for the worker daemon."}
      roots -> canonical_roots(roots, deps)
    end
  end

  defp canonical_roots(roots, deps) do
    Enum.reduce_while(roots, {:ok, []}, fn root, {:ok, acc} ->
      expanded_root = Path.expand(root)

      cond do
        not deps.dir?.(expanded_root) ->
          {:halt, {:error, "Worker daemon workspace root does not exist or is not a directory: #{expanded_root}"}}

        true ->
          case deps.canonicalize.(expanded_root) do
            {:ok, canonical_root} -> {:cont, {:ok, [canonical_root | acc]}}
            {:error, reason} -> {:halt, {:error, "Invalid worker daemon workspace root #{expanded_root}: #{inspect(reason)}"}}
          end
      end
    end)
    |> case do
      {:ok, roots} -> {:ok, Enum.reverse(roots)}
      {:error, _message} = error -> error
    end
  end
end
