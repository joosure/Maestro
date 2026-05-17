defmodule SymphonyWorkerDaemon.OrphanSweeper.SessionCandidate do
  @moduledoc false

  alias SymphonyElixir.PathSafety
  alias SymphonyWorkerDaemon.Session.Status

  @restart_lost_reasons MapSet.new(["daemon_restarted", "session_supervisor_restarted"])
  @lost_status Status.lost()

  @spec restart_orphan?(map()) :: boolean()
  def restart_orphan?(%{"status" => @lost_status, "lost_reason" => reason}) when is_binary(reason) do
    MapSet.member?(@restart_lost_reasons, reason)
  end

  def restart_orphan?(_session), do: false

  @spec os_pid(map()) :: {:ok, pos_integer()} | {:skip, String.t()}
  def os_pid(session) when is_map(session) do
    case normalize_positive_integer(Map.get(session, "os_pid") || Map.get(session, :os_pid)) do
      os_pid when is_integer(os_pid) -> {:ok, os_pid}
      nil -> {:skip, "missing_os_pid"}
    end
  end

  @spec validate_workspace(map(), [term()]) :: :ok | {:skip, String.t()}
  def validate_workspace(session, workspace_roots) when is_map(session) and is_list(workspace_roots) do
    cwd = Map.get(session, "cwd") || Map.get(session, :cwd)

    cond do
      not is_binary(cwd) or String.trim(cwd) == "" ->
        {:skip, "missing_cwd"}

      workspace_roots == [] ->
        {:skip, "missing_workspace_roots"}

      workspace_allowed?(cwd, workspace_roots) ->
        :ok

      true ->
        {:skip, "cwd_outside_workspace_roots"}
    end
  end

  defp workspace_allowed?(cwd, workspace_roots) do
    with {:ok, canonical_cwd} <- PathSafety.canonicalize(cwd),
         {:ok, canonical_roots} <- canonical_workspace_roots(workspace_roots) do
      Enum.any?(canonical_roots, &path_inside?(canonical_cwd, &1))
    else
      _reason -> false
    end
  end

  defp canonical_workspace_roots(workspace_roots) do
    workspace_roots
    |> Enum.reduce_while({:ok, []}, fn root, {:ok, acc} ->
      case PathSafety.canonicalize(to_string(root)) do
        {:ok, canonical_root} -> {:cont, {:ok, [canonical_root | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, roots} -> {:ok, Enum.reverse(roots)}
      {:error, _reason} = error -> error
    end
  end

  defp path_inside?(path, root) when is_binary(path) and is_binary(root) do
    normalized_root = String.trim_trailing(root, "/")
    path == normalized_root or String.starts_with?(path, normalized_root <> "/")
  end

  defp normalize_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp normalize_positive_integer(_value), do: nil
end
