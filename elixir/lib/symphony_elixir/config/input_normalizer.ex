defmodule SymphonyElixir.Config.InputNormalizer do
  @moduledoc false

  @spec normalize_input(map()) :: map()
  def normalize_input(config) when is_map(config) do
    config
    |> normalize_keys()
    |> drop_nil_values()
  end

  @spec normalize_keys(term()) :: term()
  def normalize_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, raw_value}, normalized ->
      Map.put(normalized, normalize_key(key), normalize_keys(raw_value))
    end)
  end

  def normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  def normalize_keys(value), do: value

  @spec normalize_optional_map(nil | map()) :: nil | map()
  def normalize_optional_map(nil), do: nil
  def normalize_optional_map(value) when is_map(value), do: normalize_keys(value)

  @spec resolve_secret_setting(nil | String.t(), term()) :: term()
  def resolve_secret_setting(nil, default_value), do: normalize_secret_value(default_value)

  def resolve_secret_setting(value, default_value) when is_binary(value) do
    case resolve_env_value(value, default_value) do
      resolved when is_binary(resolved) -> normalize_secret_value(resolved)
      resolved -> resolved
    end
  end

  @spec resolve_string_setting(nil | String.t(), String.t()) :: String.t()
  def resolve_string_setting(nil, default), do: default

  def resolve_string_setting(value, default) when is_binary(value) do
    case resolve_env_value(value, default) do
      resolved when is_binary(resolved) ->
        if resolved == "", do: default, else: resolved

      _ ->
        default
    end
  end

  @spec resolve_optional_string_setting(nil | String.t()) :: String.t() | nil
  def resolve_optional_string_setting(nil), do: nil

  def resolve_optional_string_setting(value) when is_binary(value) do
    case resolve_env_value(value, nil) do
      resolved when is_binary(resolved) -> if resolved == "", do: nil, else: resolved
      _ -> nil
    end
  end

  @spec resolve_path_value(String.t() | nil, String.t()) :: String.t()
  def resolve_path_value(value, default) when is_binary(value) do
    case normalize_path_token(value) do
      :missing ->
        default

      "" ->
        default

      path ->
        path
    end
  end

  @spec resolve_local_path_setting(nil | String.t()) :: String.t() | nil
  def resolve_local_path_setting(nil), do: nil

  def resolve_local_path_setting(value) when is_binary(value) do
    case normalize_path_token(value) do
      :missing ->
        nil

      "" ->
        nil

      path ->
        Path.expand(path)
    end
  end

  @spec resolve_platform_secrets(map(), map()) :: map()
  def resolve_platform_secrets(platform, platform_env_vars) when is_map(platform) do
    platform
    |> normalize_platform_env_refs()
    |> apply_platform_env_defaults(platform_env_vars)
  end

  def resolve_platform_secrets(_platform, _platform_env_vars), do: %{}

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  defp drop_nil_values(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      case drop_nil_values(nested) do
        nil -> acc
        normalized -> Map.put(acc, key, normalized)
      end
    end)
  end

  defp drop_nil_values(value) when is_list(value), do: Enum.map(value, &drop_nil_values/1)
  defp drop_nil_values(value), do: value

  defp resolve_env_value(value, default_value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} ->
        case System.get_env(env_name) do
          nil -> default_value
          "" -> nil
          env_value -> env_value
        end

      :error ->
        value
    end
  end

  defp normalize_path_token(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} -> resolve_env_token(env_name)
      :error -> value
    end
  end

  defp env_reference_name("${" <> rest) do
    case String.split(rest, "}", parts: 2) do
      [env_name, ""] -> validate_env_reference_name(env_name)
      _ -> :error
    end
  end

  defp env_reference_name("$" <> env_name) do
    validate_env_reference_name(env_name)
  end

  defp env_reference_name(_value), do: :error

  defp validate_env_reference_name(env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp resolve_env_token(env_name) do
    case System.get_env(env_name) do
      nil -> :missing
      env_value -> env_value
    end
  end

  defp normalize_secret_value(value) when is_binary(value) do
    if value == "", do: nil, else: value
  end

  defp normalize_secret_value(_value), do: nil

  defp normalize_platform_env_refs(platform) when is_map(platform) do
    Enum.reduce(platform, %{}, fn {key, value}, acc ->
      Map.put(acc, key, resolve_platform_value(value))
    end)
  end

  defp apply_platform_env_defaults(platform, platform_env_vars) when is_map(platform) do
    Enum.reduce(platform_env_vars, platform, fn {key, env_name}, acc ->
      current_value = Map.get(acc, key)
      resolved = resolve_secret_setting(current_value, System.get_env(env_name))

      if is_nil(resolved) do
        acc
      else
        Map.put(acc, key, resolved)
      end
    end)
  end

  defp resolve_platform_value(value) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, _env_name} -> resolve_secret_setting(value, nil)
      :error -> value
    end
  end

  defp resolve_platform_value(value), do: value
end
