defmodule SymphonyElixir.Agent.ExecutionPlan.Schema.Validation do
  @moduledoc """
  Shared canonical execution-plan schema validation helpers.

  This module owns generic field-shape checks and generic validation error
  codes. Domain adoption schemas compose these helpers with their own field
  contracts and domain-specific checks.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.ErrorCodes.Validation, as: ValidationErrorCodes
  alias SymphonyElixir.Agent.ExecutionPlan.Fields

  @type error :: map()
  @type path :: [String.t() | non_neg_integer()]

  @spec collect_unknown_keys([error()], map(), [String.t()], path()) :: [error()]
  def collect_unknown_keys(errors, record, allowed_keys, path) when is_map(record) and is_list(allowed_keys) do
    unknown_errors =
      record
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_keys))
      |> Enum.map(fn key ->
        %{code: ValidationErrorCodes.unknown_key(), path: path ++ [key], message: "Unknown non-extension key is not allowed."}
      end)

    errors ++ unknown_errors
  end

  @spec collect_required_keys([error()], map(), [String.t()], path()) :: [error()]
  def collect_required_keys(errors, record, required_keys, path) when is_map(record) and is_list(required_keys) do
    required_errors =
      required_keys
      |> Enum.reject(&Map.has_key?(record, &1))
      |> Enum.map(fn key ->
        %{code: ValidationErrorCodes.missing_required_field(), path: path ++ [key], message: "Required field is missing."}
      end)

    errors ++ required_errors
  end

  @spec collect_string_field([error()], map(), String.t(), path()) :: [error()]
  def collect_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be a non-empty string."}]
    else
      errors
    end
  end

  @spec collect_nullable_string_field([error()], map(), String.t(), path()) :: [error()]
  def collect_nullable_string_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_nil(Map.get(record, key)) and not non_empty_string?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be null or a non-empty string."}]
    else
      errors
    end
  end

  @spec collect_enum_field([error()], map(), String.t(), (term() -> boolean()), path()) :: [error()]
  def collect_enum_field(errors, record, key, validator, path) when is_function(validator, 1) do
    if Map.has_key?(record, key) and not validator.(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_enum(), path: path ++ [key], message: "Field must be an allowed value."}]
    else
      errors
    end
  end

  @spec collect_boolean_field([error()], map(), String.t(), path()) :: [error()]
  def collect_boolean_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_boolean(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be a boolean."}]
    else
      errors
    end
  end

  @spec collect_string_list_field([error()], map(), String.t(), path()) :: [error()]
  def collect_string_list_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not string_list?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be a list of non-empty strings."}]
    else
      errors
    end
  end

  @spec collect_enum_list_field([error()], map(), String.t(), (term() -> boolean()), path(), String.t()) :: [error()]
  def collect_enum_list_field(errors, record, key, validator, path, message) when is_function(validator, 1) do
    value = Map.get(record, key)

    if Map.has_key?(record, key) and (not string_list?(value) or Enum.any?(value, &(not validator.(&1)))) do
      errors ++ [%{code: ValidationErrorCodes.invalid_enum(), path: path ++ [key], message: message}]
    else
      errors
    end
  end

  @spec collect_map_field([error()], map(), String.t(), path()) :: [error()]
  def collect_map_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_map(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be an object."}]
    else
      errors
    end
  end

  @spec collect_optional_map_field([error()], map(), String.t(), path()) :: [error()]
  def collect_optional_map_field(errors, record, key, path), do: collect_map_field(errors, record, key, path)

  @spec collect_nullable_map_field([error()], map(), String.t(), path()) :: [error()]
  def collect_nullable_map_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not is_nil(Map.get(record, key)) and not is_map(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be null or an object."}]
    else
      errors
    end
  end

  @spec collect_timestamp_field([error()], map(), String.t(), path()) :: [error()]
  def collect_timestamp_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not rfc3339?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be an RFC 3339 timestamp."}]
    else
      errors
    end
  end

  @spec collect_positive_integer_field([error()], map(), String.t(), path()) :: [error()]
  def collect_positive_integer_field(errors, record, key, path) do
    if Map.has_key?(record, key) and not positive_integer?(Map.get(record, key)) do
      errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [key], message: "Field must be a positive integer."}]
    else
      errors
    end
  end

  @spec collect_extensions([error()], map(), path()) :: [error()]
  def collect_extensions(errors, record, path) when is_map(record) do
    case Map.fetch(record, Fields.extensions()) do
      :error ->
        errors

      {:ok, extensions} when is_map(extensions) ->
        extension_errors =
          extensions
          |> Map.keys()
          |> Enum.reject(&namespaced_key?/1)
          |> Enum.map(fn key ->
            %{
              code: ValidationErrorCodes.invalid_extension_key(),
              path: path ++ [Fields.extensions(), key],
              message: "Extension keys must be namespaced."
            }
          end)

        errors ++ extension_errors

      {:ok, _extensions} ->
        errors ++ [%{code: ValidationErrorCodes.invalid_type(), path: path ++ [Fields.extensions()], message: "Extensions must be an object."}]
    end
  end

  @spec validation_error([error()], String.t()) :: map()
  def validation_error(errors, message), do: %{code: ValidationErrorCodes.schema_invalid(), message: message, errors: errors}

  @spec non_empty_string?(term()) :: boolean()
  def non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  @spec positive_integer?(term()) :: boolean()
  def positive_integer?(value), do: is_integer(value) and value > 0

  @spec string_list?(term()) :: boolean()
  def string_list?(values) when is_list(values), do: Enum.all?(values, &non_empty_string?/1)
  def string_list?(_values), do: false

  @spec rfc3339?(term()) :: boolean()
  def rfc3339?(value) when is_binary(value), do: match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  def rfc3339?(_value), do: false

  @spec namespaced_key?(term()) :: boolean()
  def namespaced_key?(value) when is_binary(value), do: String.contains?(value, ".")
  def namespaced_key?(_value), do: false
end
