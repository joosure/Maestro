defmodule SymphonyElixir.Tracker.ConfigAccess do
  @moduledoc false

  @doc """
  Returns `true` when `value` is `nil` or a whitespace-only string.

  ## Examples

      iex> blank?(nil)
      true
      iex> blank?("  ")
      true
      iex> blank?("hello")
      false
  """
  @spec blank?(term()) :: boolean()
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(nil), do: true
  def blank?(_value), do: false

  @doc """
  Looks up `key` in `map`, trying the string key first then the existing atom key.
  Returns `nil` if neither exists.
  """
  @spec map_field(map() | nil, String.t()) :: term()
  def map_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  def map_field(_map, _key), do: nil

  @doc """
  Safely looks up `key` as an existing atom in `map`.

  Uses `String.to_existing_atom/1` to avoid atom table pollution.
  Returns `nil` if the atom does not exist or is not a key in the map.
  """
  @spec map_get_existing_atom(map(), String.t()) :: term()
  def map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  @doc """
  Returns `value` unchanged when it is a map, otherwise returns `%{}`.
  """
  @spec normalize_optional_map(term()) :: map()
  def normalize_optional_map(value) when is_map(value), do: value
  def normalize_optional_map(_value), do: %{}

  @doc """
  Extracts a named sub-map from the tracker's `provider` config.

  Returns the value at `field_name` inside the provider map, normalized
  to a map (returns `%{}` if the field is missing or not a map).

  ## Examples

      iex> tracker = %{provider: %{"platform" => %{"workspace_id" => "123"}}}
      iex> provider_field(tracker, "platform")
      %{"workspace_id" => "123"}

      iex> provider_field(%{provider: %{}}, "platform")
      %{}
  """
  @spec provider_field(map(), String.t()) :: map()
  def provider_field(tracker, field_name) when is_map(tracker) and is_binary(field_name) do
    alias SymphonyElixir.Tracker.Config, as: TrackerConfig

    tracker
    |> TrackerConfig.provider()
    |> map_field(field_name)
    |> normalize_optional_map()
  end
end
