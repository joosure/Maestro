defmodule SymphonyElixir.Agent.DynamicTool.Source do
  @moduledoc """
  Behaviour and dispatch helpers for provider-neutral dynamic tool sources.
  """

  @composite_source Module.concat(["SymphonyElixir", "Agent", "DynamicTool", "CompositeSource"])

  @type context :: term()
  @type tool_result :: {:success, term()} | {:failure, term()} | {:error, term()}

  @callback default_context(keyword()) :: context()
  @callback kind(context()) :: String.t() | nil
  @callback tools(context(), keyword()) :: [map()]
  @callback environment(context(), keyword()) :: map()
  @callback execute(context(), String.t() | nil, term(), keyword()) :: tool_result()

  @spec default() :: module()
  def default do
    cond do
      source = Application.get_env(:symphony_elixir, :dynamic_tool_source) ->
        source

      is_list(Application.get_env(:symphony_elixir, :dynamic_tool_sources)) ->
        @composite_source

      true ->
        @composite_source
    end
  end

  @spec from_opts(keyword()) :: module()
  def from_opts(opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :dynamic_tool_source) ->
        Keyword.fetch!(opts, :dynamic_tool_source)

      Keyword.has_key?(opts, :dynamic_tool_sources) ->
        @composite_source

      true ->
        default()
    end
  end

  @spec default_context(module(), keyword()) :: context()
  def default_context(source, opts \\ []) when is_atom(source) and is_list(opts) do
    source.default_context(opts)
  end

  @spec kind(module(), context()) :: String.t() | nil
  def kind(source, source_context) when is_atom(source) do
    source.kind(source_context)
  end

  @spec tools(module(), context(), keyword()) :: [map()]
  def tools(source, source_context, opts \\ []) when is_atom(source) and is_list(opts) do
    source.tools(source_context, opts)
  end

  @spec environment(module(), context(), keyword()) :: map()
  def environment(source, source_context, opts \\ []) when is_atom(source) and is_list(opts) do
    source.environment(source_context, opts)
  end

  @spec execute(module(), context(), String.t() | nil, term(), keyword()) :: tool_result()
  def execute(source, source_context, tool, arguments, opts \\ [])
      when is_atom(source) and is_list(opts) do
    source.execute(source_context, tool, arguments, opts)
  end
end
