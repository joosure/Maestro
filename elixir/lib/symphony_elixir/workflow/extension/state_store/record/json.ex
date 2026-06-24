defmodule SymphonyElixir.Workflow.Extension.StateStore.Record.Json do
  @moduledoc false

  @type key_policy :: :string_keys | :atom_or_string_keys

  @spec compatible?(term(), key_policy()) :: boolean()
  def compatible?(value, _key_policy) when is_struct(value), do: false

  def compatible?(value, key_policy) when is_map(value) do
    Enum.all?(value, fn {key, nested_value} ->
      key?(key, key_policy) and compatible?(nested_value, key_policy)
    end)
  end

  def compatible?(value, key_policy) when is_list(value) do
    Enum.all?(value, &compatible?(&1, key_policy))
  end

  def compatible?(value, _key_policy) when is_binary(value), do: true
  def compatible?(value, _key_policy) when is_boolean(value), do: true
  def compatible?(value, _key_policy) when is_integer(value), do: true
  def compatible?(value, _key_policy) when is_float(value), do: true
  def compatible?(nil, _key_policy), do: true
  def compatible?(_value, _key_policy), do: false

  @spec key?(term(), key_policy()) :: boolean()
  def key?(key, :string_keys), do: is_binary(key)
  def key?(key, :atom_or_string_keys), do: is_binary(key) or is_atom(key)
end
