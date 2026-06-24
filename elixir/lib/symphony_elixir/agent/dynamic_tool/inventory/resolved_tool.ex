defmodule SymphonyElixir.Agent.DynamicTool.Inventory.ResolvedTool do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Metadata

  @default_side_effect Metadata.Contract.default_side_effect()
  @default_schema_version Metadata.Contract.default_schema_version()

  @enforce_keys [:capability, :tool]
  defstruct capability: nil,
            tool: nil,
            side_effect: @default_side_effect,
            source_kind: nil,
            schema_version: @default_schema_version,
            alias_of: nil

  @type t :: %__MODULE__{
          capability: String.t(),
          tool: String.t(),
          side_effect: String.t(),
          source_kind: String.t() | nil,
          schema_version: String.t(),
          alias_of: String.t() | nil
        }

  @spec new(map() | keyword()) :: {:ok, t()} | :error
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    with {:ok, capability} <- string_attr(attrs, :capability),
         {:ok, tool} <- string_attr(attrs, :tool),
         {:ok, side_effect} <- side_effect_attr(attrs),
         {:ok, schema_version} <- optional_string_attr(attrs, :schema_version, @default_schema_version),
         {:ok, source_kind} <- optional_string_attr(attrs, :source_kind, nil),
         {:ok, alias_of} <- optional_string_attr(attrs, :alias_of, nil) do
      {:ok,
       %__MODULE__{
         capability: capability,
         tool: tool,
         side_effect: side_effect,
         source_kind: source_kind,
         schema_version: schema_version,
         alias_of: alias_of
       }}
    else
      :error -> :error
    end
  end

  def new(_attrs), do: :error

  @spec alias?(t() | map()) :: boolean()
  def alias?(%__MODULE__{alias_of: alias_of}), do: normalized_string?(alias_of)
  def alias?(%{alias_of: alias_of}), do: normalized_string?(alias_of)
  def alias?(_tool), do: false

  defp side_effect_attr(attrs) do
    with {:ok, side_effect} <- string_attr(attrs, :side_effect),
         true <- side_effect in Metadata.Contract.side_effect_classes() do
      {:ok, side_effect}
    else
      _invalid -> :error
    end
  end

  defp string_attr(attrs, key) when is_atom(key) do
    attrs
    |> attr_value(key)
    |> normalize_string()
    |> case do
      nil -> :error
      value -> {:ok, value}
    end
  end

  defp optional_string_attr(attrs, key, default) when is_atom(key) do
    case attr_presence(attrs, key) do
      :missing ->
        {:ok, default}

      {:present, value} ->
        normalize_optional_string(value, default)
    end
  end

  defp attr_value(attrs, key) when is_map(attrs) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> nil
    end
  end

  defp attr_value(attrs, key) when is_list(attrs) and is_atom(key), do: Keyword.get(attrs, key)
  defp attr_value(_attrs, _key), do: nil

  defp attr_presence(attrs, key) when is_map(attrs) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> {:present, Map.get(attrs, key)}
      Map.has_key?(attrs, string_key) -> {:present, Map.get(attrs, string_key)}
      true -> :missing
    end
  end

  defp attr_presence(attrs, key) when is_list(attrs) and is_atom(key) do
    if Keyword.has_key?(attrs, key), do: {:present, Keyword.get(attrs, key)}, else: :missing
  end

  defp attr_presence(_attrs, _key), do: :missing

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(_value), do: nil

  defp normalize_optional_string(nil, default), do: {:ok, default}

  defp normalize_optional_string(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, default}
      value -> {:ok, value}
    end
  end

  defp normalize_optional_string(_value, _default), do: :error

  defp normalized_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp normalized_string?(_value), do: false
end
