defmodule SymphonyWorkerDaemon.Protocol.Validation.Fields do
  @moduledoc false

  @spec allowed_nested_keys(map(), String.t(), [String.t()]) :: :ok | {:error, term()}
  def allowed_nested_keys(request, field, allowed_keys) when is_map(request) and is_binary(field) and is_list(allowed_keys) do
    case Map.get(request, field) do
      nil -> :ok
      value when is_map(value) -> allowed_keys(value, field, allowed_keys)
      _value -> {:error, {:payload_invalid, field}}
    end
  end

  @spec allowed_keys(map(), String.t(), [String.t()]) :: :ok | {:error, term()}
  def allowed_keys(map, field, allowed_keys) when is_map(map) and is_binary(field) and is_list(allowed_keys) do
    allowed = MapSet.new(allowed_keys)

    unknown =
      map
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.sort()

    case unknown do
      [] -> :ok
      keys -> {:error, {:payload_unknown_fields, field, keys}}
    end
  end

  @spec optional_map(map(), String.t()) :: :ok | {:error, term()}
  def optional_map(map, field) when is_map(map) and is_binary(field) do
    case Map.get(map, field) do
      nil -> :ok
      value when is_map(value) -> :ok
      _value -> {:error, {:payload_invalid, field}}
    end
  end

  @spec optional_string(map(), String.t()) :: :ok | {:error, term()}
  def optional_string(map, field) when is_map(map) and is_binary(field) do
    case Map.get(map, field) do
      nil -> :ok
      value when is_binary(value) -> :ok
      _value -> {:error, {:payload_invalid, field}}
    end
  end
end
