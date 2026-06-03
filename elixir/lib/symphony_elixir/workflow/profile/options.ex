defmodule SymphonyElixir.Workflow.Profile.Options do
  @moduledoc """
  Shared schema and validators for workflow-profile option maps.

  Profile modules own which options exist by declaring a schema. This module
  derives default option maps and applies the common validation rules so new
  profiles do not need to reimplement parser-shaped checks.
  """

  @name_pattern ~r/^[a-z][a-z0-9_]*$/

  @type option_type ::
          :boolean
          | :name
          | :string_list
          | {:enum, [term()]}
          | {:map, schema()}
          | {:name_list, keyword()}

  @type option_spec :: %{
          required(:type) => option_type(),
          optional(:default) => term(),
          optional(:description) => String.t()
        }

  @type schema :: %{String.t() => option_spec()}

  @spec default_options(schema()) :: map()
  def default_options(schema) when is_map(schema) do
    Map.new(schema, fn {key, spec} -> {key, default_for_spec(spec)} end)
  end

  @spec validate(String.t(), map(), schema()) :: :ok | {:error, term()}
  def validate(profile_kind, options, schema)
      when is_binary(profile_kind) and is_map(options) and is_map(schema) do
    validate_map(profile_kind, options, schema, nil)
  end

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

  defp validate_map(profile_kind, options, schema, parent_path)
       when is_map(options) and is_map(schema) do
    with :ok <- reject_unknown_schema_key(profile_kind, options, schema, parent_path) do
      Enum.reduce_while(schema, :ok, fn {key, spec}, :ok ->
        path = option_path(parent_path, key)
        value = Map.get(options, key, default_for_spec(spec))

        case validate_spec(profile_kind, path, value, spec) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp reject_unknown_schema_key(profile_kind, options, schema, parent_path) do
    case Map.keys(options) -- Map.keys(schema) do
      [] ->
        :ok

      [unknown_key | _rest] ->
        {:error, {:unknown_profile_option, profile_kind, option_path(parent_path, unknown_key)}}
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: {:map, nested_schema}})
       when is_map(nested_schema) do
    case value do
      nested_options when is_map(nested_options) ->
        validate_map(profile_kind, nested_options, nested_schema, path)

      value ->
        invalid_option(profile_kind, path, value)
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: :boolean}) do
    if is_boolean(value) do
      :ok
    else
      invalid_option(profile_kind, path, value)
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: {:enum, allowed_values}})
       when is_list(allowed_values) do
    if value in allowed_values do
      :ok
    else
      invalid_option(profile_kind, path, value)
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: :name}) do
    if valid_name?(value) do
      :ok
    else
      invalid_option(profile_kind, path, value)
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: :string_list}) do
    if is_list(value) and Enum.all?(value, &non_empty_string?/1) do
      :ok
    else
      invalid_option(profile_kind, path, value)
    end
  end

  defp validate_spec(profile_kind, path, value, %{type: {:name_list, opts}})
       when is_list(opts) do
    min_count = Keyword.get(opts, :min, 0)
    unique? = Keyword.get(opts, :unique, false)

    cond do
      not is_list(value) ->
        invalid_option(profile_kind, path, value)

      length(value) < min_count ->
        invalid_option(profile_kind, path, value)

      not Enum.all?(value, &valid_name?/1) ->
        invalid_option(profile_kind, path, value)

      unique? and Enum.uniq(value) != value ->
        invalid_option(profile_kind, path, value)

      true ->
        :ok
    end
  end

  defp default_for_spec(%{type: {:map, nested_schema}} = spec) when is_map(nested_schema) do
    nested_defaults = default_options(nested_schema)

    case Map.fetch(spec, :default) do
      {:ok, default} when is_map(default) -> deep_merge(nested_defaults, default)
      :error -> nested_defaults
    end
  end

  defp default_for_spec(%{default: default}), do: default

  defp option_path(nil, key), do: key
  defp option_path(parent_path, key), do: "#{parent_path}.#{key}"

  defp invalid_option(profile_kind, path, value),
    do: {:error, {:invalid_profile_option, profile_kind, path, value}}

  defp valid_name?(value) when is_binary(value), do: String.match?(value, @name_pattern)
  defp valid_name?(_value), do: false

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end
end
