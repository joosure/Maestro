defmodule SymphonyElixir.Agent.DynamicTool.Source do
  @moduledoc """
  Behaviour and dispatch helpers for provider-neutral dynamic tool sources.
  """

  alias SymphonyElixir.Agent.DynamicTool.Source.{Config, Environment, Kind}
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  @composite_source SymphonyElixir.Agent.DynamicTool.CompositeSource

  @type context :: term()
  @type tool_result :: {:success, term()} | {:failure, term()} | {:error, term()}

  @callback default_context(keyword()) :: context()
  @callback kind(context()) :: String.t() | nil
  @callback tools(context(), keyword()) :: [map()]
  @callback environment(context(), keyword()) :: map()
  @callback canonical_tool(context(), String.t() | nil) :: String.t() | nil
  @callback execute(context(), String.t() | nil, term(), keyword()) :: tool_result()
  @callback execute_canonical(context(), String.t() | nil, String.t() | nil, term(), keyword()) :: tool_result()

  @optional_callbacks canonical_tool: 2, execute_canonical: 5

  @required_callbacks [
    default_context: 1,
    kind: 1,
    tools: 2,
    environment: 2,
    execute: 4
  ]

  @spec composite_source() :: module()
  def composite_source, do: @composite_source

  @spec default() :: module()
  def default do
    Config.default_source(@composite_source)
    |> validate!()
  end

  @spec from_opts(keyword()) :: module()
  def from_opts(opts) when is_list(opts) do
    opts
    |> Config.source_from_opts(@composite_source)
    |> validate!()
  end

  @spec valid?(term()) :: boolean()
  def valid?(source) when is_atom(source) do
    Code.ensure_loaded?(source) and
      Enum.all?(@required_callbacks, fn {function, arity} ->
        function_exported?(source, function, arity)
      end)
  end

  def valid?(_source), do: false

  @spec validate!(term()) :: module()
  def validate!(source) when is_atom(source) do
    if valid?(source) do
      source
    else
      raise ArgumentError, "invalid dynamic tool source: #{inspect(source)}"
    end
  end

  def validate!(source), do: raise(ArgumentError, "invalid dynamic tool source: #{inspect(source)}")

  @spec default_context(module(), keyword()) :: context()
  def default_context(source, opts \\ []) when is_atom(source) and is_list(opts) do
    source = validate!(source)
    source.default_context(opts)
  end

  @spec kind(module(), context()) :: String.t() | nil
  def kind(source, source_context) when is_atom(source) do
    source = validate!(source)

    source.kind(source_context)
    |> Kind.normalize!()
  end

  @spec tools(module(), context(), keyword()) :: [map()]
  def tools(source, source_context, opts \\ []) when is_atom(source) and is_list(opts) do
    source = validate!(source)

    case source.tools(source_context, opts) do
      tools when is_list(tools) -> tools
      tools -> raise ArgumentError, "invalid dynamic tool source tools: expected a list, got #{inspect(tools)}"
    end
  end

  @spec tool_specs(module(), context(), keyword()) :: [ToolSpec.t()]
  def tool_specs(source, source_context, opts \\ []) when is_atom(source) and is_list(opts) do
    case source |> tools(source_context, opts) |> ToolSpec.normalize_many_strict() do
      {:ok, tool_specs} ->
        tool_specs

      {:error, errors} ->
        raise ArgumentError, "invalid dynamic tool source tool specs: #{inspect(errors)}"
    end
  end

  @spec environment(module(), context(), keyword()) :: map()
  def environment(source, source_context, opts \\ []) when is_atom(source) and is_list(opts) do
    source = validate!(source)

    source.environment(source_context, opts)
    |> Environment.normalize!()
  end

  @spec execute(module(), context(), String.t() | nil, term(), keyword()) :: tool_result()
  def execute(source, source_context, tool, arguments, opts \\ [])
      when is_atom(source) and is_list(opts) do
    source = validate!(source)
    source.execute(source_context, tool, arguments, opts)
  end

  @spec execute_canonical(module(), context(), String.t() | nil, String.t() | nil, term(), keyword()) :: tool_result()
  def execute_canonical(source, source_context, provider_tool, canonical_tool, arguments, opts \\ [])
      when is_atom(source) and is_list(opts) do
    source = validate!(source)

    if function_exported?(source, :execute_canonical, 5) do
      source.execute_canonical(source_context, provider_tool, canonical_tool, arguments, opts)
    else
      source.execute(source_context, canonical_tool, arguments, opts)
    end
  end

  @spec canonical_tool(module(), context(), String.t() | nil) :: String.t() | nil
  def canonical_tool(source, source_context, tool) when is_atom(source) do
    source = validate!(source)

    if function_exported?(source, :canonical_tool, 2) do
      source.canonical_tool(source_context, tool)
    else
      tool
    end
  end
end
