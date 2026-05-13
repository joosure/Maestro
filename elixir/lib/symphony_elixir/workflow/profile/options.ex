defmodule SymphonyElixir.Workflow.Profile.Options do
  @moduledoc """
  Shared validators for workflow-profile option maps.

  Profile modules own which options exist, but the low-level validation rules
  should stay consistent across profiles.
  """

  @name_pattern ~r/^[a-z][a-z0-9_]*$/

  @spec value(map(), map(), String.t()) :: term()
  def value(options, defaults, key) when is_map(options) and is_map(defaults) and is_binary(key) do
    Map.get(options, key, Map.fetch!(defaults, key))
  end

  @spec reject_unknown(String.t(), map(), [String.t()]) :: :ok | {:error, term()}
  def reject_unknown(profile_kind, options, known_keys)
      when is_binary(profile_kind) and is_map(options) and is_list(known_keys) do
    case Map.keys(options) -- known_keys do
      [] -> :ok
      [unknown_key | _rest] -> {:error, {:unknown_profile_option, profile_kind, unknown_key}}
    end
  end

  @spec validate_boolean(String.t(), map(), map(), String.t()) :: :ok | {:error, term()}
  def validate_boolean(profile_kind, options, defaults, key)
      when is_binary(profile_kind) and is_map(options) and is_map(defaults) and is_binary(key) do
    case value(options, defaults, key) do
      value when is_boolean(value) -> :ok
      value -> {:error, {:invalid_profile_option, profile_kind, key, value}}
    end
  end

  @spec validate_enum(String.t(), map(), map(), String.t(), [term()]) :: :ok | {:error, term()}
  def validate_enum(profile_kind, options, defaults, key, allowed_values)
      when is_binary(profile_kind) and is_map(options) and is_map(defaults) and is_binary(key) and is_list(allowed_values) do
    case value(options, defaults, key) do
      value ->
        if value in allowed_values do
          :ok
        else
          {:error, {:invalid_profile_option, profile_kind, key, value}}
        end
    end
  end

  @spec validate_name(String.t(), map(), map(), String.t()) :: :ok | {:error, term()}
  def validate_name(profile_kind, options, defaults, key)
      when is_binary(profile_kind) and is_map(options) and is_map(defaults) and is_binary(key) do
    case value(options, defaults, key) do
      value when is_binary(value) ->
        if String.match?(value, @name_pattern) do
          :ok
        else
          {:error, {:invalid_profile_option, profile_kind, key, value}}
        end

      value ->
        {:error, {:invalid_profile_option, profile_kind, key, value}}
    end
  end

  @spec validate_string_list(String.t(), map(), map(), String.t()) :: :ok | {:error, term()}
  def validate_string_list(profile_kind, options, defaults, key)
      when is_binary(profile_kind) and is_map(options) and is_map(defaults) and is_binary(key) do
    case value(options, defaults, key) do
      values when is_list(values) ->
        if Enum.all?(values, &non_empty_string?/1) do
          :ok
        else
          {:error, {:invalid_profile_option, profile_kind, key, values}}
        end

      value ->
        {:error, {:invalid_profile_option, profile_kind, key, value}}
    end
  end

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false
end
