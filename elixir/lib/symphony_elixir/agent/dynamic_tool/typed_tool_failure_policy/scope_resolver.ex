defmodule SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.ScopeResolver do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Context.RuntimeMetadata
  alias SymphonyElixir.Agent.DynamicTool.TypedToolFailurePolicy.{FailureScope, ResourceIdentity, Server}

  @spec scope(Context.t(), String.t() | nil, term(), keyword()) :: {:ok, FailureScope.t()} | :unscoped
  def scope(%Context{} = tool_context, tool, arguments, opts) do
    runtime_metadata = runtime_metadata(tool_context)

    with %ResourceIdentity{} = identity <- resource_identity(runtime_metadata, arguments, opts),
         run_id when is_binary(run_id) <- run_scope(opts, runtime_metadata),
         tool_name when is_binary(tool_name) <- normalize_tool_name(tool),
         {:ok, scope} <- FailureScope.new(run_id, identity, tool_name) do
      {:ok, scope}
    else
      _unscoped -> :unscoped
    end
  end

  def scope(_tool_context, _tool, _arguments, _opts), do: :unscoped

  @spec runtime_metadata(Context.t()) :: map()
  def runtime_metadata(%Context{} = context), do: Context.runtime_metadata(context)
  def runtime_metadata(_context), do: RuntimeMetadata.empty()

  @spec run_scope(keyword(), map()) :: String.t() | nil
  def run_scope(opts, runtime_metadata) do
    scoped_value(opts, runtime_metadata, :run_id) ||
      scoped_value(opts, runtime_metadata, :session_id) ||
      scoped_value(opts, runtime_metadata, :turn_id)
  end

  @spec scoped_value(keyword(), map(), atom()) :: term()
  def scoped_value(opts, runtime_metadata, key) when is_list(opts) and is_map(runtime_metadata) and is_atom(key) do
    Keyword.get(opts, key) || RuntimeMetadata.value(runtime_metadata, key)
  end

  @spec normalize_tool_name(term()) :: String.t() | nil
  def normalize_tool_name(tool) when is_binary(tool) do
    case String.trim(tool) do
      "" -> nil
      tool -> tool
    end
  end

  def normalize_tool_name(_tool), do: nil

  @spec argument_keys(term()) :: [String.t()]
  def argument_keys(arguments) when is_map(arguments) do
    arguments
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  def argument_keys(_arguments), do: []

  defp resource_identity(runtime_metadata, arguments, opts) do
    opts
    |> Server.resource_identity_fun()
    |> case do
      fun when is_function(fun, 2) -> fun.(runtime_metadata, arguments)
      nil -> nil
    end
    |> ResourceIdentity.normalize()
  end
end
