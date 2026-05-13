defmodule SymphonyElixir.AgentProvider.ToolInventory do
  @moduledoc """
  Resolves provider-specific Dynamic Tool inventory rendering options.

  Business semantics stay in `SymphonyElixir.Agent.DynamicTool.Inventory`.
  Provider adapters own only the presentation details required to call tools
  through their native transport.
  """

  alias SymphonyElixir.AgentProvider.Registry

  @spec render_opts(String.t() | nil) :: keyword()
  def render_opts(kind) when is_binary(kind) do
    case Registry.fetch(kind) do
      adapter when is_atom(adapter) and not is_nil(adapter) ->
        adapter_render_opts(adapter)

      _adapter ->
        []
    end
  end

  def render_opts(_kind), do: []

  defp adapter_render_opts(adapter) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :dynamic_tool_inventory_opts, 0) do
      case adapter.dynamic_tool_inventory_opts() do
        opts when is_list(opts) -> opts
        _opts -> []
      end
    else
      []
    end
  end
end
