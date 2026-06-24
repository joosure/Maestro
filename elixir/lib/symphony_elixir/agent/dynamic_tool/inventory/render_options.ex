defmodule SymphonyElixir.Agent.DynamicTool.Inventory.RenderOptions do
  @moduledoc false

  @provider_callable_name_key :provider_callable_name
  @provider_callable_label_key :provider_callable_label
  @provider_callable_note_key :provider_callable_note

  @default_provider_callable_label "Tool to call"
  @default_provider_callable_note "The provider adapter generated these callable names for the active session."

  defstruct provider_callable_name: nil,
            provider_callable_label: @default_provider_callable_label,
            provider_callable_note: @default_provider_callable_note

  @type callable_name :: (String.t() -> String.t())

  @type t :: %__MODULE__{
          provider_callable_name: callable_name() | nil,
          provider_callable_label: String.t(),
          provider_callable_note: String.t()
        }

  @type raw :: t() | keyword() | map() | nil

  @spec provider_callable_name_key() :: atom()
  def provider_callable_name_key, do: @provider_callable_name_key

  @spec provider_callable_label_key() :: atom()
  def provider_callable_label_key, do: @provider_callable_label_key

  @spec provider_callable_note_key() :: atom()
  def provider_callable_note_key, do: @provider_callable_note_key

  @spec default_provider_callable_label() :: String.t()
  def default_provider_callable_label, do: @default_provider_callable_label

  @spec default_provider_callable_note() :: String.t()
  def default_provider_callable_note, do: @default_provider_callable_note

  @spec normalize(raw()) :: t()
  def normalize(%__MODULE__{} = options) do
    %__MODULE__{
      provider_callable_name: normalize_callable(options.provider_callable_name),
      provider_callable_label: normalized_string(options.provider_callable_label, @default_provider_callable_label),
      provider_callable_note: normalized_string(options.provider_callable_note, @default_provider_callable_note)
    }
  end

  def normalize(options) when is_list(options) do
    %__MODULE__{
      provider_callable_name: normalize_callable(Keyword.get(options, @provider_callable_name_key)),
      provider_callable_label: normalized_string(Keyword.get(options, @provider_callable_label_key), @default_provider_callable_label),
      provider_callable_note: normalized_string(Keyword.get(options, @provider_callable_note_key), @default_provider_callable_note)
    }
  end

  def normalize(options) when is_map(options) do
    %__MODULE__{
      provider_callable_name: normalize_callable(map_value(options, @provider_callable_name_key)),
      provider_callable_label: normalized_string(map_value(options, @provider_callable_label_key), @default_provider_callable_label),
      provider_callable_note: normalized_string(map_value(options, @provider_callable_note_key), @default_provider_callable_note)
    }
  end

  def normalize(_options), do: %__MODULE__{}

  @spec provider_callable_name(t()) :: callable_name() | nil
  def provider_callable_name(%__MODULE__{provider_callable_name: callable_name})
      when is_function(callable_name, 1),
      do: callable_name

  def provider_callable_name(_options), do: nil

  @spec provider_callable_label(t()) :: String.t()
  def provider_callable_label(%__MODULE__{provider_callable_label: label}) when is_binary(label), do: label
  def provider_callable_label(_options), do: @default_provider_callable_label

  @spec provider_callable_note(t()) :: String.t()
  def provider_callable_note(%__MODULE__{provider_callable_note: note}) when is_binary(note), do: note
  def provider_callable_note(_options), do: @default_provider_callable_note

  @spec provider_callable?(t()) :: boolean()
  def provider_callable?(%__MODULE__{} = options), do: is_function(provider_callable_name(options), 1)
  def provider_callable?(_options), do: false

  defp normalize_callable(callable_name) when is_function(callable_name, 1), do: callable_name
  defp normalize_callable(_callable_name), do: nil

  defp normalized_string(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      value -> value
    end
  end

  defp normalized_string(_value, default), do: default

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end
end
