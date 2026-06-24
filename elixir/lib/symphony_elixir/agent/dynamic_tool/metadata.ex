defmodule SymphonyElixir.Agent.DynamicTool.Metadata do
  @moduledoc false

  alias __MODULE__.Contract
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec

  @side_effect_classes Contract.side_effect_classes()
  @default_schema_version Contract.default_schema_version()
  @side_effect_key Contract.side_effect()
  @schema_version_key Contract.schema_version()
  @risk_flags_key Contract.risk_flags()
  @capability_key Contract.capability()
  @tool_alias_of_key Contract.tool_alias_of()
  @source_kind_key Contract.source_kind()
  @operator_only_key Contract.operator_only()

  defstruct side_effect: nil,
            side_effect_error: :missing,
            schema_version: @default_schema_version,
            risk_flags: [],
            capability: nil,
            tool_alias_of: nil,
            source_kind: nil,
            operator_only?: false

  @type t :: %__MODULE__{
          side_effect: String.t() | nil,
          side_effect_error: :missing | {:invalid, String.t()} | nil,
          schema_version: String.t(),
          risk_flags: [String.t()],
          capability: String.t() | nil,
          tool_alias_of: String.t() | nil,
          source_kind: String.t() | nil,
          operator_only?: boolean()
        }

  @spec default() :: t()
  def default, do: %__MODULE__{}

  @spec from_tool_specs(term()) :: %{String.t() => t()}
  def from_tool_specs(tool_specs) when is_list(tool_specs) do
    {_seen, metadata} =
      Enum.reduce(tool_specs, {MapSet.new(), %{}}, fn tool_spec, {seen, metadata} ->
        case ToolSpec.normalize(tool_spec) do
          {:ok, %ToolSpec{name: name}} ->
            if MapSet.member?(seen, name) do
              {seen, metadata}
            else
              {MapSet.put(seen, name), Map.put(metadata, name, normalize(tool_spec))}
            end

          :error ->
            {seen, metadata}
        end
      end)

    metadata
  end

  def from_tool_specs(_tool_specs), do: %{}

  @spec from_metadata_map(term()) :: %{String.t() => t()}
  def from_metadata_map(metadata_by_tool) when is_map(metadata_by_tool) do
    metadata_by_tool
    |> Enum.flat_map(fn
      {tool, metadata} when is_binary(tool) and tool != "" ->
        [{tool, normalize(metadata)}]

      _entry ->
        []
    end)
    |> Map.new()
  end

  def from_metadata_map(_metadata_by_tool), do: %{}

  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = metadata), do: metadata

  def normalize(tool_spec_or_metadata) when is_map(tool_spec_or_metadata) do
    {side_effect, side_effect_error} = side_effect(tool_spec_or_metadata)

    %__MODULE__{
      side_effect: side_effect,
      side_effect_error: side_effect_error,
      schema_version: string_field(tool_spec_or_metadata, @schema_version_key, @default_schema_version),
      risk_flags: risk_flags(tool_spec_or_metadata),
      capability: string_field(tool_spec_or_metadata, @capability_key, nil),
      tool_alias_of: string_field(tool_spec_or_metadata, @tool_alias_of_key, nil),
      source_kind: string_field(tool_spec_or_metadata, @source_kind_key, nil),
      operator_only?: boolean_field(tool_spec_or_metadata, @operator_only_key, false)
    }
  end

  def normalize(_tool_spec_or_metadata), do: default()

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = metadata) do
    %{}
    |> maybe_put_string(@side_effect_key, metadata.side_effect)
    |> Map.put(@schema_version_key, metadata.schema_version)
    |> Map.put(@risk_flags_key, metadata.risk_flags)
    |> maybe_put_string(@capability_key, metadata.capability)
    |> maybe_put_string(@tool_alias_of_key, metadata.tool_alias_of)
    |> maybe_put_string(@source_kind_key, metadata.source_kind)
    |> maybe_put_boolean(@operator_only_key, metadata.operator_only?)
  end

  @spec to_map_by_tool(%{String.t() => t()}) :: map()
  def to_map_by_tool(metadata_by_tool) when is_map(metadata_by_tool) do
    Map.new(metadata_by_tool, fn {tool, metadata} -> {tool, metadata |> normalize() |> to_map()} end)
  end

  @spec valid_side_effect?(t()) :: boolean()
  def valid_side_effect?(%__MODULE__{side_effect_error: nil, side_effect: side_effect}),
    do: side_effect in @side_effect_classes

  def valid_side_effect?(_metadata), do: false

  @spec side_effect_error(t()) :: :missing | {:invalid, String.t()} | nil
  def side_effect_error(%__MODULE__{side_effect_error: error}), do: error
  def side_effect_error(_metadata), do: :missing

  defp side_effect(tool_spec_or_metadata) when is_map(tool_spec_or_metadata) do
    case field_value_presence(tool_spec_or_metadata, @side_effect_key) do
      :missing ->
        {nil, :missing}

      {:present, raw_side_effect} ->
        case normalize_side_effect_value(raw_side_effect) do
          side_effect when side_effect in @side_effect_classes -> {side_effect, nil}
          nil -> {nil, {:invalid, inspect(raw_side_effect)}}
          side_effect -> {nil, {:invalid, side_effect}}
        end
    end
  end

  defp risk_flags(tool_spec_or_metadata) do
    case field_value(tool_spec_or_metadata, @risk_flags_key) do
      flags when is_list(flags) ->
        flags
        |> Enum.map(&normalize_flag/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _flags ->
        []
    end
  end

  defp string_field(map, field, default) do
    map
    |> field_value(field)
    |> normalize_string()
    |> case do
      nil -> default
      value -> value
    end
  end

  defp field_value(map, field) when is_map(map) and is_binary(field) do
    Map.get(map, field)
  end

  defp field_value(_map, _field), do: nil

  defp field_value_presence(map, field) when is_map(map) and is_binary(field) do
    if Map.has_key?(map, field) do
      {:present, Map.get(map, field)}
    else
      :missing
    end
  end

  defp field_value_presence(_map, _field), do: :missing

  defp boolean_field(map, field, default) do
    case field_value(map, field) do
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp maybe_put_string(map, _key, nil), do: map
  defp maybe_put_string(map, _key, ""), do: map
  defp maybe_put_string(map, key, value) when is_binary(value), do: Map.put(map, key, value)

  defp maybe_put_boolean(map, _key, false), do: map
  defp maybe_put_boolean(map, key, true), do: Map.put(map, key, true)

  defp normalize_side_effect_value(value) do
    normalize_string(value)
  end

  defp normalize_flag(value), do: value |> normalize_string() |> downcase_string()

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(_value), do: nil

  defp downcase_string(value) when is_binary(value), do: String.downcase(value)
  defp downcase_string(value), do: value
end
