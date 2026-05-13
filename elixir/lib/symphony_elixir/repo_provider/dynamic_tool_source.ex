defmodule SymphonyElixir.RepoProvider.DynamicToolSource do
  @moduledoc """
  Dynamic tool source backed by the configured repo-provider facade.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Repo.DynamicToolContext
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Config, as: RepoConfig

  @spec default_context(keyword()) :: RepoConfig.t()
  def default_context(_opts \\ []), do: RepoConfig.current!()

  @spec kind(term()) :: String.t() | nil
  def kind(source_context) when is_map(source_context), do: RepoProvider.current_kind(source_context)
  def kind(_source_context), do: nil

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    RepoProvider.dynamic_tools(source_context)
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(source_context, opts \\ [])

  def environment(source_context, _opts) when is_map(source_context) do
    RepoProvider.runtime_env(source_context)
    |> Map.new()
  end

  def environment(_source_context, _opts), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    case resolve_repo_context(source_context, opts) do
      {:ok, repo} -> RepoProvider.execute_dynamic_tool(repo, tool, arguments, opts)
      {:error, reason} -> DynamicToolContext.failure(reason)
    end
  end

  def execute(_source_context, _tool, _arguments, _opts) do
    {:error, :repo_provider_dynamic_tool_source_context_unavailable}
  end

  defp resolve_repo_context(repo, opts) when is_map(repo) and is_list(opts) do
    DynamicToolContext.resolve_repo_path(repo, RepoConfig.path(repo), opts, source_kind: "repo_provider")
  end
end
