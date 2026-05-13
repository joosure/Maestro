defmodule SymphonyElixir.AgentProvider.EventSummaryMapper.Access do
  @moduledoc false

  @spec path_value(term(), [atom() | String.t()]) :: term()
  def path_value(value, []), do: value

  def path_value(%{} = map, [key | rest]) do
    case map_value(map, key) do
      nil -> nil
      value -> path_value(value, rest)
    end
  end

  def path_value(_value, _path), do: nil

  @spec map_value(term(), atom() | String.t()) :: term()
  def map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  def map_value(%{} = map, key) when is_binary(key) do
    Map.get(map, key) || existing_atom_value(map, key)
  end

  def map_value(_value, _key), do: nil

  defp existing_atom_value(map, key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
