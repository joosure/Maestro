defmodule SymphonyWorkerDaemon.WorkspaceManager do
  @moduledoc false

  alias SymphonyWorkerDaemon.WorkspaceManager.Paths

  @type validation_result :: {:ok, Path.t()} | {:error, term()}

  @spec validate_workspace(term(), keyword()) :: validation_result()
  def validate_workspace(workspace_request, opts \\ []) when is_list(opts) do
    with {:ok, cwd} <- Paths.requested_cwd(workspace_request),
         {:ok, canonical_cwd} <- Paths.canonicalize(cwd),
         {:ok, roots} <- Paths.canonical_roots(Keyword.get(opts, :workspace_roots, [])),
         :ok <- Paths.validate_under_allowed_root(canonical_cwd, roots) do
      {:ok, canonical_cwd}
    end
  end

  @spec cleanup_workspace(Path.t(), keyword()) :: :ok | {:error, term()}
  def cleanup_workspace(workspace, opts \\ []) when is_binary(workspace) and is_list(opts) do
    if Keyword.get(opts, :delete_workspace?, false) do
      with {:ok, canonical_workspace} <- Paths.canonicalize(workspace),
           {:ok, roots} <- Paths.canonical_roots(Keyword.get(opts, :workspace_roots, [])),
           :ok <- Paths.validate_under_allowed_root(canonical_workspace, roots),
           :ok <- Paths.validate_cleanup_target(canonical_workspace, roots) do
        File.rm_rf(canonical_workspace)
        :ok
      end
    else
      :ok
    end
  end
end
