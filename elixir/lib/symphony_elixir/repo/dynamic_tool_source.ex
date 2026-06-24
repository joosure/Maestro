defmodule SymphonyElixir.Repo.DynamicToolSource do
  @moduledoc """
  Dynamic tool source backed by the provider-neutral repo-core facade.
  """

  @behaviour SymphonyElixir.Agent.DynamicTool.Source

  alias SymphonyElixir.Agent.DynamicTool.ResultRecorder
  alias SymphonyElixir.Config
  alias SymphonyElixir.Repo.Context
  alias SymphonyElixir.Repo.DynamicToolContext
  alias SymphonyElixir.Repo.ToolExecutor

  @spec default_context(keyword()) :: map()
  def default_context(_opts \\ []) do
    Config.settings!().repo
  end

  @spec kind(term()) :: String.t()
  def kind(_source_context), do: "repo"

  @spec tools(term(), keyword()) :: [map()]
  def tools(source_context, opts \\ [])

  def tools(source_context, _opts) when is_map(source_context) do
    ToolExecutor.tool_specs(source_context)
  end

  def tools(_source_context, _opts), do: []

  @spec environment(term(), keyword()) :: map()
  def environment(_source_context, _opts \\ []), do: %{}

  @spec execute(term(), String.t() | nil, term(), keyword()) :: SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(source_context, tool, arguments, opts \\ [])

  def execute(source_context, tool, arguments, opts) when is_map(source_context) and is_list(opts) do
    case resolve_repo_context(source_context, opts) do
      {:ok, repo} ->
        result = ToolExecutor.execute(repo, tool, arguments, opts)
        _record_result = ResultRecorder.record_result("repo", repo, tool, arguments, result, opts)
        result

      {:error, reason} ->
        DynamicToolContext.failure(reason)
    end
  end

  def execute(_source_context, _tool, _arguments, _opts) do
    {:error, :repo_dynamic_tool_source_context_unavailable}
  end

  defp resolve_repo_context(repo, opts) when is_map(repo) and is_list(opts) do
    DynamicToolContext.resolve_repo_path(repo, Context.path(repo), opts, source_kind: "repo")
  end
end
