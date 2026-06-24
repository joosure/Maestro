defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Aliases do
  @moduledoc """
  Presentation-boundary aliases for workflow structured execution plan tools.

  Canonical workflow plan tools are provider-neutral. Provider-facing names are
  accepted only at Dynamic Tool exposure/execution boundaries and are
  normalized before dispatch reaches the executor.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Metadata, Spec}
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.ProviderContext
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Contract

  @snapshot_suffix "snapshot"
  @upsert_suffix "upsert"
  @update_item_suffix "update_item"
  @render_workpad_suffix "render_workpad"

  @canonical_operations [
    {Contract.snapshot_tool(), @snapshot_suffix},
    {Contract.upsert_tool(), @upsert_suffix},
    {Contract.update_item_tool(), @update_item_suffix},
    {Contract.render_workpad_tool(), @render_workpad_suffix}
  ]

  @canonical_names MapSet.new(Enum.map(@canonical_operations, &elem(&1, 0)))

  @spec snapshot_tool() :: String.t()
  defdelegate snapshot_tool, to: Contract

  @spec upsert_tool() :: String.t()
  defdelegate upsert_tool, to: Contract

  @spec update_item_tool() :: String.t()
  defdelegate update_item_tool, to: Contract

  @spec render_workpad_tool() :: String.t()
  defdelegate render_workpad_tool, to: Contract

  @spec canonical_tool_names() :: [String.t()]
  def canonical_tool_names, do: Enum.map(@canonical_operations, &elem(&1, 0))

  @spec canonical_tool?(term()) :: boolean()
  def canonical_tool?(tool) when is_binary(tool), do: MapSet.member?(@canonical_names, tool)
  def canonical_tool?(_tool), do: false

  @doc """
  Returns the canonical workflow tool name for a canonical or registered alias.

  Provider/tracker aliases are resolved only from the runtime provider contexts
  selected by the Dynamic Tool source. Unknown names return `:error` and remain
  unsupported by the executor.
  """
  @provider_key_field ProviderContext.provider_key_key()
  @alias_prefix_field ProviderContext.alias_prefix_key()

  @spec canonical_name(term(), term()) :: {:ok, String.t()} | :error
  def canonical_name(tool, provider_contexts \\ [])

  def canonical_name(tool, provider_contexts) when is_binary(tool) do
    cond do
      canonical_tool?(tool) -> {:ok, tool}
      is_binary(canonical_tool = alias_to_canonical(provider_contexts)[tool]) -> {:ok, canonical_tool}
      true -> :error
    end
  end

  def canonical_name(_tool, _provider_contexts), do: :error

  @doc """
  Builds provider-facing Dynamic Tool specs for runtime provider contexts.

  The returned specs keep the canonical workflow capability metadata from the
  canonical specs and only replace the presentation tool name.
  """
  @spec provider_alias_specs([map()], term()) :: [map()]
  def provider_alias_specs(canonical_specs, provider_contexts)

  def provider_alias_specs(canonical_specs, provider_contexts) when is_list(canonical_specs) do
    specs_by_name = Map.new(canonical_specs, &{Map.fetch!(&1, Spec.name_key()), &1})

    provider_contexts
    |> provider_entries()
    |> Enum.flat_map(&provider_alias_specs_for_entry(specs_by_name, &1))
  end

  def provider_alias_specs(_canonical_specs, _provider_contexts), do: []

  defp alias_to_canonical(provider_contexts) do
    for %{@alias_prefix_field => alias_prefix} <- provider_entries(provider_contexts),
        {canonical_name, suffix} <- @canonical_operations,
        into: %{} do
      {"#{alias_prefix}_#{suffix}", canonical_name}
    end
  end

  defp provider_alias_specs_for_entry(specs_by_name, %{@alias_prefix_field => alias_prefix}) do
    Enum.map(@canonical_operations, fn {canonical_name, suffix} ->
      specs_by_name
      |> Map.fetch!(canonical_name)
      |> Map.put(Spec.name_key(), "#{alias_prefix}_#{suffix}")
      |> Map.put(Metadata.Contract.tool_alias_of(), canonical_name)
    end)
  end

  defp provider_entries(provider_contexts) do
    provider_contexts
    |> List.wrap()
    |> Enum.flat_map(&provider_entry/1)
    |> dedupe_entries()
  end

  defp provider_entry(%{} = context) do
    case context |> Map.get(@provider_key_field) |> normalize_string() do
      nil -> []
      provider_key -> [%{@provider_key_field => provider_key, @alias_prefix_field => ProviderContext.alias_prefix(provider_key)}]
    end
  end

  defp provider_entry(_provider_context), do: []

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()
  defp normalize_string(_value), do: nil

  defp dedupe_entries(entries) do
    {_seen, deduped} =
      Enum.reduce(entries, {MapSet.new(), []}, fn entry, {seen, deduped} ->
        key = Map.fetch!(entry, @provider_key_field)

        if MapSet.member?(seen, key) do
          {seen, deduped}
        else
          {MapSet.put(seen, key), [entry | deduped]}
        end
      end)

    Enum.reverse(deduped)
  end
end
