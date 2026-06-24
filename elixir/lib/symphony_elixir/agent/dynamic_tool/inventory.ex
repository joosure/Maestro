defmodule SymphonyElixir.Agent.DynamicTool.Inventory do
  @moduledoc """
  Resolves typed tool capabilities to concrete runtime tool names.
  """

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Inventory.{Renderer, RenderOptions, ResolutionError, ResolvedTool}
  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Spec

  @type resolved_tool :: ResolvedTool.t()
  @type resolution_error :: ResolutionError.t()

  @spec typed_tools(map()) :: [resolved_tool()]
  def typed_tools(tool_context) when is_map(tool_context) do
    tool_context
    |> Context.tool_specs()
    |> Enum.flat_map(&typed_tool_from_spec(&1, tool_context))
  end

  def typed_tools(_tool_context), do: []

  @spec authoritative_typed_tools(map()) :: [resolved_tool()]
  def authoritative_typed_tools(tool_context) when is_map(tool_context) do
    tool_context
    |> typed_tools()
    |> Enum.reject(&ResolvedTool.alias?/1)
  end

  def authoritative_typed_tools(_tool_context), do: []

  @spec resolve_required(map(), [term()]) :: {:ok, [resolved_tool()]} | {:error, resolution_error()}
  def resolve_required(tool_context, capabilities)

  def resolve_required(tool_context, capabilities)
      when is_map(tool_context) and is_list(capabilities) do
    with {:ok, typed_capabilities} <- normalize_required_capabilities(capabilities) do
      typed_tools = authoritative_typed_tools(tool_context)

      Enum.reduce_while(typed_capabilities, {:ok, []}, fn capability, {:ok, resolved} ->
        case resolve_capability(typed_tools, capability) do
          {:ok, tool} ->
            {:cont, {:ok, [tool | resolved]}}

          {:error, %ResolutionError{} = reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
        {:error, %ResolutionError{}} = error -> error
      end
    end
  end

  def resolve_required(_tool_context, _capabilities),
    do: {:error, ResolutionError.invalid_required_capability(nil)}

  @spec render(map(), RenderOptions.raw()) :: String.t()
  def render(tool_context, opts \\ [])

  def render(tool_context, opts) when is_map(tool_context) do
    case inventory_tools(tool_context) do
      tools ->
        Renderer.render(tools, opts)
    end
  end

  def render(_tool_context, _opts), do: render(Context.empty())

  @spec typed_capability?(term()) :: boolean()
  def typed_capability?(capability) when is_binary(capability) do
    String.trim(capability) != ""
  end

  def typed_capability?(_capability), do: false

  defp normalize_required_capabilities(capabilities) when is_list(capabilities) do
    Enum.reduce_while(capabilities, {:ok, []}, fn capability, {:ok, normalized} ->
      if typed_capability?(capability) do
        {:cont, {:ok, [String.trim(capability) | normalized]}}
      else
        {:halt, {:error, ResolutionError.invalid_required_capability(capability)}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, %ResolutionError{}} = error -> error
    end
  end

  defp typed_tool_from_spec(tool_spec, tool_context) when is_map(tool_spec) and is_map(tool_context) do
    name = Map.get(tool_spec, Spec.name_key())

    if is_binary(name) do
      typed_tool_from_name(name, tool_context)
    else
      []
    end
  end

  defp typed_tool_from_spec(_tool_spec, _tool_context), do: []

  defp typed_tool_from_name(name, tool_context) do
    metadata = Context.metadata_for(tool_context, name)

    if is_binary(metadata.capability) and Metadata.valid_side_effect?(metadata) do
      case ResolvedTool.new(%{
             capability: metadata.capability,
             tool: name,
             side_effect: metadata.side_effect,
             source_kind: metadata.source_kind,
             schema_version: metadata.schema_version,
             alias_of: metadata.tool_alias_of
           }) do
        {:ok, %ResolvedTool{} = tool} ->
          [tool]

        :error ->
          []
      end
    else
      []
    end
  end

  defp resolve_capability(tools, capability) do
    matches = Enum.filter(tools, &(&1.capability == capability))

    case matches do
      [tool] -> {:ok, tool}
      [] -> {:error, ResolutionError.missing_typed_tool(capability)}
      matches -> {:error, ResolutionError.ambiguous_typed_tool(capability, Enum.map(matches, & &1.tool))}
    end
  end

  defp inventory_tools(tool_context) do
    authoritative_typed_tools(tool_context)
  end
end
