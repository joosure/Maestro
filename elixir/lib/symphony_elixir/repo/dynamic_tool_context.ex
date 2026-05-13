defmodule SymphonyElixir.Repo.DynamicToolContext do
  @moduledoc """
  Resolves repository context for dynamic tool execution.

  Dynamic tools run inside Symphony, not inside the agent provider process. Any
  source that consumes local repository facts must resolve relative repo paths
  against the captured issue workspace before invoking repo or provider code.
  """

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.Config
  alias SymphonyElixir.Workspace.Paths

  @type resolution_error :: %{
          code: atom(),
          message: String.t(),
          details: map()
        }

  @spec resolve_repo_path(map(), Path.t() | nil, keyword(), keyword()) ::
          {:ok, map()} | {:error, resolution_error()}
  def resolve_repo_path(repo, path, opts, resolver_opts \\ [])
      when is_map(repo) and is_list(opts) and is_list(resolver_opts) do
    source_kind = Keyword.fetch!(resolver_opts, :source_kind)
    path = normalize_path(path)

    cond do
      is_nil(path) ->
        {:ok, repo}

      Path.type(path) == :absolute ->
        {:ok, put_repo_path(repo, path)}

      workspace = workspace_path(opts) ->
        case validate_workspace(workspace) do
          :ok -> {:ok, put_repo_path(repo, Path.expand(path, workspace))}
          {:error, reason} -> {:error, invalid_workspace_error(source_kind, path, workspace, reason)}
        end

      true ->
        {:error, missing_workspace_error(source_kind, path)}
    end
  end

  @spec failure(resolution_error()) :: {:failure, map()}
  def failure(%{code: code, message: message, details: details}) do
    {:failure,
     %{
       "error" => %{
         "code" => to_string(code),
         "message" => message,
         "details" => Serializer.json_safe_value(details)
       }
     }}
  end

  @spec workspace_path(keyword()) :: Path.t() | nil
  def workspace_path(opts) when is_list(opts) do
    [Keyword.get(opts, :workspace), runtime_target_workspace(opts)]
    |> Enum.find_value(fn
      workspace when is_binary(workspace) ->
        case String.trim(workspace) do
          "" -> nil
          normalized -> Path.expand(normalized)
        end

      _workspace ->
        nil
    end)
  end

  defp runtime_target_workspace(opts) do
    case Keyword.get(opts, :agent_runtime_target) do
      %{workspace_path: workspace} when is_binary(workspace) -> workspace
      _target -> nil
    end
  end

  defp validate_workspace(workspace) do
    case Config.settings() do
      {:ok, settings} -> Paths.validate_local_workspace_path(workspace, settings.workspace.root)
      {:error, _reason} -> :ok
    end
  end

  defp missing_workspace_error(source_kind, path) do
    %{
      code: error_code(source_kind, :workspace_required),
      message: "#{source_label(source_kind)} dynamic tool requires workspace context to resolve relative repo path #{inspect(path)}.",
      details: %{
        source_kind: source_kind,
        repo_path: path
      }
    }
  end

  defp invalid_workspace_error(source_kind, path, workspace, reason) do
    %{
      code: error_code(source_kind, :workspace_invalid),
      message: "#{source_label(source_kind)} dynamic tool received an invalid workspace context for relative repo path #{inspect(path)}.",
      details: %{
        source_kind: source_kind,
        repo_path: path,
        workspace_path: workspace,
        reason: reason
      }
    }
  end

  defp error_code("repo_provider", :workspace_required), do: :repo_provider_dynamic_tool_workspace_required
  defp error_code("repo_provider", :workspace_invalid), do: :repo_provider_dynamic_tool_workspace_invalid
  defp error_code("repo", :workspace_required), do: :repo_dynamic_tool_workspace_required
  defp error_code("repo", :workspace_invalid), do: :repo_dynamic_tool_workspace_invalid
  defp error_code(_source_kind, :workspace_required), do: :dynamic_tool_workspace_required
  defp error_code(_source_kind, :workspace_invalid), do: :dynamic_tool_workspace_invalid

  defp source_label("repo_provider"), do: "Repo-provider"
  defp source_label("repo"), do: "Repo"
  defp source_label(source_kind), do: source_kind

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_path(_path), do: nil

  defp put_repo_path(%_{} = repo, path), do: Map.put(repo, :path, path)
  defp put_repo_path(repo, path) when is_map(repo), do: Map.put(repo, :path, path)
end
