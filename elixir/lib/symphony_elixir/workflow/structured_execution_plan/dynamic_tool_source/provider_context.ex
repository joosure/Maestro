defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.ProviderContext do
  @moduledoc """
  Canonical provider context contract for structured-plan Dynamic Tool exposure.

  Raw tracker/provider context shapes are accepted only at this Dynamic Tool
  source boundary and normalized to `%{provider_key: provider_key}` before alias
  generation or execution dispatch sees them.
  """

  @provider_key_key :provider_key
  @provider_key_string_key "provider_key"
  @provider_kind_key :provider_kind
  @provider_kind_string_key "provider_kind"
  @tracker_kind_key :tracker_kind
  @tracker_kind_string_key "tracker_kind"
  @kind_key :kind
  @kind_string_key "kind"
  @tracker_key :tracker
  @tracker_string_key "tracker"
  @provider_contexts_key :provider_contexts
  @provider_contexts_string_key "provider_contexts"
  @alias_prefix_key :alias_prefix

  @type t :: %{required(:provider_key) => String.t()}

  @spec provider_key_key() :: atom()
  def provider_key_key, do: @provider_key_key

  @spec alias_prefix_key() :: atom()
  def alias_prefix_key, do: @alias_prefix_key

  @spec tracker_key() :: atom()
  def tracker_key, do: @tracker_key

  @spec tracker_string_key() :: String.t()
  def tracker_string_key, do: @tracker_string_key

  @spec provider_contexts_key() :: atom()
  def provider_contexts_key, do: @provider_contexts_key

  @spec provider_contexts_string_key() :: String.t()
  def provider_contexts_string_key, do: @provider_contexts_string_key

  @spec alias_prefix(String.t()) :: String.t()
  def alias_prefix(provider_key) when is_binary(provider_key), do: "#{provider_key}_plan"

  @spec contexts_from_map(term()) :: [t()]
  def contexts_from_map(%{} = map) do
    map
    |> raw_map_value(@provider_contexts_key, @provider_contexts_string_key)
    |> from_input()
  end

  def contexts_from_map(_map), do: []

  @spec provider_key(term()) :: String.t() | nil
  def provider_key(%{} = map) do
    map_value(map, @provider_key_key, @provider_key_string_key) ||
      map_value(map, @provider_kind_key, @provider_kind_string_key) ||
      map_value(map, @tracker_kind_key, @tracker_kind_string_key) ||
      map_value(map, @kind_key, @kind_string_key)
  end

  def provider_key(_map), do: nil

  @spec from_input(term()) :: [t()]
  def from_input(contexts) when is_list(contexts) do
    contexts
    |> Enum.flat_map(&from_input/1)
    |> dedupe()
  end

  def from_input(%{} = context) do
    case provider_key(context) do
      nil -> []
      provider_key -> [canonical(provider_key)]
    end
  end

  def from_input(provider_key) when is_binary(provider_key) do
    case normalize_string(provider_key) do
      nil -> []
      normalized_provider_key -> [canonical(normalized_provider_key)]
    end
  end

  def from_input(_contexts), do: []

  @spec dedupe([t()]) :: [t()]
  def dedupe(contexts) when is_list(contexts) do
    {_seen, deduped} =
      Enum.reduce(contexts, {MapSet.new(), []}, fn
        %{@provider_key_key => provider_key} = context, {seen, deduped} when is_binary(provider_key) ->
          if MapSet.member?(seen, provider_key) do
            {seen, deduped}
          else
            {MapSet.put(seen, provider_key), [context | deduped]}
          end

        _context, acc ->
          acc
      end)

    Enum.reverse(deduped)
  end

  def dedupe(_contexts), do: []

  defp canonical(provider_key), do: %{@provider_key_key => provider_key}

  defp raw_map_value(%{} = map, atom_key, string_key), do: Map.get(map, atom_key) || Map.get(map, string_key)

  defp map_value(map, atom_key, string_key)
  defp map_value(%{} = map, atom_key, string_key), do: normalize_value(Map.get(map, atom_key) || Map.get(map, string_key))

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_binary(value), do: normalize_string(value)
  defp normalize_value(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()
  defp normalize_value(_value), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
