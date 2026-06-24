defmodule SymphonyElixir.Agent.DynamicTool.CompositeSource.Entry do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Source.Kind
  alias SymphonyElixir.Agent.DynamicTool.Spec

  defstruct source: nil,
            source_context: nil,
            source_kind: nil,
            tool_specs: []

  @type t :: %__MODULE__{
          source: module(),
          source_context: term(),
          source_kind: String.t() | nil,
          tool_specs: [map()]
        }

  @spec new(keyword() | map()) :: t() | nil
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    source = value(attrs, :source, nil)

    if is_atom(source) and not is_nil(source) do
      %__MODULE__{
        source: source,
        source_context: value(attrs, :source_context, nil),
        source_kind: Kind.normalize(value(attrs, :source_kind, nil)),
        tool_specs: tool_specs(value(attrs, :tool_specs, []))
      }
    end
  end

  @spec normalize(term()) :: t() | nil
  def normalize(%__MODULE__{} = entry), do: new(entry)
  def normalize(entry) when is_map(entry) or is_list(entry), do: new(entry)
  def normalize(_entry), do: nil

  defp tool_specs(tool_specs) when is_list(tool_specs), do: Enum.flat_map(tool_specs, &canonical_tool_spec/1)
  defp tool_specs(_tool_specs), do: []

  defp canonical_tool_spec(tool_spec) when is_map(tool_spec) do
    case Spec.normalize(tool_spec) do
      {:ok, normalized_spec} ->
        [Map.merge(normalized_spec, tool_spec |> Metadata.normalize() |> Metadata.to_map())]

      :error ->
        []
    end
  end

  defp canonical_tool_spec(_tool_spec), do: []

  defp value(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp value(attrs, key, default) when is_map(attrs) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> default
    end
  end
end
