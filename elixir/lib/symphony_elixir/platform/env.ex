defmodule SymphonyElixir.Platform.Env do
  @moduledoc false

  @env_name_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @spec value(map(), String.t()) :: String.t() | nil
  def value(env_map, name) when is_map(env_map) and is_binary(name) do
    case Map.get(env_map, name) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: nil, else: value

      _value ->
        nil
    end
  end

  @spec value(map(), String.t(), String.t()) :: String.t()
  def value(env_map, name, default) when is_binary(default) do
    value(env_map, name) || default
  end

  @spec env_name(map(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def env_name(env_map, name, default) do
    env_map
    |> value(name, default)
    |> validate_env_name(name)
  end

  @spec configured_env_name(map(), String.t()) :: :missing | {:ok, String.t()} | {:error, String.t()}
  def configured_env_name(env_map, name) do
    case value(env_map, name) do
      nil -> :missing
      value -> validate_env_name(value, name)
    end
  end

  @spec nested(term(), [atom()]) :: term()
  def nested(value, []), do: value

  def nested(value, [key | rest]) when is_map(value) and is_atom(key) do
    value
    |> option_value(key)
    |> nested(rest)
  end

  def nested(_value, _path), do: nil

  @spec normalize_string(term()) :: String.t() | nil
  def normalize_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  def normalize_string(_value), do: nil

  defp validate_env_name(value, name) when is_binary(value) do
    if Regex.match?(@env_name_pattern, value) do
      {:ok, value}
    else
      {:error, "#{name} must contain an environment variable name, got #{inspect(value)}"}
    end
  end

  defp option_value(value, key) do
    case Map.fetch(value, key) do
      {:ok, option} -> option
      :error -> Map.get(value, Atom.to_string(key))
    end
  end
end
