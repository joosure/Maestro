defmodule SymphonyElixir.Agent.DynamicTool.ToolSpec do
  @moduledoc false

  @name_pattern ~r/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/
  @name_key "name"
  @description_key "description"
  @input_schema_key "inputSchema"
  @schema_type_key "type"
  @schema_properties_key "properties"
  @schema_required_key "required"
  @schema_items_key "items"
  @schema_additional_properties_key "additionalProperties"
  @schema_all_of_key "allOf"
  @schema_any_of_key "anyOf"
  @schema_one_of_key "oneOf"
  @schema_array_type "array"
  @schema_boolean_type "boolean"
  @schema_integer_type "integer"
  @schema_null_type "null"
  @schema_number_type "number"
  @schema_object_type "object"
  @schema_string_type "string"
  @schema_combinator_keys [@schema_all_of_key, @schema_any_of_key, @schema_one_of_key]
  @default_input_schema %{@schema_type_key => @schema_object_type, @schema_additional_properties_key => true}

  @json_schema_types [
    @schema_array_type,
    @schema_boolean_type,
    @schema_integer_type,
    @schema_null_type,
    @schema_number_type,
    @schema_object_type,
    @schema_string_type
  ]

  @enforce_keys [:name, :description, :input_schema]
  defstruct name: nil,
            description: nil,
            input_schema: @default_input_schema

  defmodule Error do
    @moduledoc false

    @enforce_keys [:index, :reason]
    defstruct index: nil,
              reason: nil,
              tool_name: nil

    @type reason :: :invalid_collection | :invalid_spec | {:duplicate_name, String.t()}

    @type t :: %__MODULE__{
            index: non_neg_integer() | nil,
            reason: reason(),
            tool_name: String.t() | nil
          }

    @spec invalid_collection() :: t()
    def invalid_collection, do: %__MODULE__{index: nil, reason: :invalid_collection}

    @spec invalid_spec(non_neg_integer()) :: t()
    def invalid_spec(index), do: %__MODULE__{index: index, reason: :invalid_spec}

    @spec duplicate_name(non_neg_integer(), String.t()) :: t()
    def duplicate_name(index, name), do: %__MODULE__{index: index, reason: {:duplicate_name, name}, tool_name: name}
  end

  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | %{optional(String.t()) => json_value()}
  @type json_object :: %{optional(String.t()) => json_value()}
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: json_object()
        }

  @spec normalize_many_strict(term()) :: {:ok, [t()]} | {:error, [Error.t()]}
  def normalize_many_strict(tool_specs) when is_list(tool_specs) do
    {_seen, specs, errors} =
      tool_specs
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), [], []}, fn {tool_spec, index}, {seen, specs, errors} ->
        case normalize(tool_spec) do
          {:ok, %__MODULE__{name: name} = normalized} ->
            if MapSet.member?(seen, name) do
              {seen, specs, [Error.duplicate_name(index, name) | errors]}
            else
              {MapSet.put(seen, name), [normalized | specs], errors}
            end

          :error ->
            {seen, specs, [Error.invalid_spec(index) | errors]}
        end
      end)

    case Enum.reverse(errors) do
      [] -> {:ok, Enum.reverse(specs)}
      errors -> {:error, errors}
    end
  end

  def normalize_many_strict(_tool_specs), do: {:error, [Error.invalid_collection()]}

  @spec normalize(term()) :: {:ok, t()} | :error
  def normalize(%__MODULE__{} = tool_spec), do: {:ok, tool_spec}

  def normalize(tool_spec) when is_map(tool_spec) do
    with {:ok, name} <- normalize_name(tool_spec),
         {:ok, description} <- normalize_description(tool_spec, name),
         {:ok, input_schema} <- normalize_input_schema(tool_spec) do
      {:ok, %__MODULE__{name: name, description: description, input_schema: input_schema}}
    else
      :error -> :error
    end
  end

  def normalize(_tool_spec), do: :error

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = tool_spec) do
    %{
      @name_key => tool_spec.name,
      @description_key => tool_spec.description,
      @input_schema_key => tool_spec.input_schema
    }
  end

  @spec to_maps([t()]) :: [map()]
  def to_maps(tool_specs) when is_list(tool_specs), do: Enum.map(tool_specs, &to_map/1)

  @spec valid_name?(term()) :: boolean()
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_pattern, name)
  def valid_name?(_name), do: false

  @spec name_key() :: String.t()
  def name_key, do: @name_key

  @spec description_key() :: String.t()
  def description_key, do: @description_key

  @spec input_schema_key() :: String.t()
  def input_schema_key, do: @input_schema_key

  defp normalize_name(tool_spec) do
    case string_field(tool_spec, @name_key) do
      name when is_binary(name) and name != "" ->
        if valid_name?(name), do: {:ok, name}, else: :error

      _name ->
        :error
    end
  end

  defp normalize_description(tool_spec, name) do
    case string_field(tool_spec, @description_key) do
      description when is_binary(description) and description != "" ->
        {:ok, description}

      _description ->
        {:ok, "Execute Symphony dynamic tool #{name}."}
    end
  end

  defp normalize_input_schema(tool_spec) do
    with {:ok, raw_schema} <- fetch_string_key(tool_spec, @input_schema_key),
         {:ok, schema} <- json_encodable(raw_schema),
         schema when is_map(schema) <- schema,
         @schema_object_type <- Map.get(schema, @schema_type_key),
         :ok <- validate_schema(schema) do
      {:ok, schema}
    else
      _invalid -> :error
    end
  end

  defp string_field(map, field) do
    case Map.get(map, field) do
      value when is_binary(value) -> String.trim(value)
      _value -> nil
    end
  end

  defp fetch_string_key(map, key) when is_map(map) and is_binary(key) do
    if Map.has_key?(map, key), do: {:ok, Map.get(map, key)}, else: :error
  end

  defp validate_schema(schema) when is_map(schema) do
    with :ok <- validate_type_keyword(schema),
         :ok <- validate_schema_properties(schema),
         :ok <- validate_schema_required(schema),
         :ok <- validate_schema_items(schema),
         :ok <- validate_schema_combinators(schema),
         :ok <- validate_additional_properties(schema) do
      :ok
    end
  end

  defp validate_schema(_schema), do: :error

  defp validate_type_keyword(%{@schema_type_key => type}), do: validate_type(type)
  defp validate_type_keyword(_schema), do: :ok

  defp validate_type(type) when is_binary(type), do: if(type in @json_schema_types, do: :ok, else: :error)

  defp validate_type(types) when is_list(types) do
    if Enum.all?(types, &(is_binary(&1) and &1 in @json_schema_types)), do: :ok, else: :error
  end

  defp validate_type(_type), do: :error

  defp validate_schema_properties(%{@schema_properties_key => properties}) when is_map(properties) do
    properties
    |> Enum.reduce_while(:ok, fn
      {name, schema}, :ok when is_binary(name) and name != "" ->
        case validate_schema(schema) do
          :ok -> {:cont, :ok}
          :error -> {:halt, :error}
        end

      _entry, :ok ->
        {:halt, :error}
    end)
  end

  defp validate_schema_properties(%{@schema_properties_key => _properties}), do: :error
  defp validate_schema_properties(_schema), do: :ok

  defp validate_schema_required(%{@schema_required_key => required}) when is_list(required) do
    if Enum.all?(required, &is_binary/1), do: :ok, else: :error
  end

  defp validate_schema_required(%{@schema_required_key => _required}), do: :error
  defp validate_schema_required(_schema), do: :ok

  defp validate_schema_items(%{@schema_items_key => items}) when is_map(items), do: validate_schema(items)

  defp validate_schema_items(%{@schema_items_key => items}) when is_list(items) do
    if Enum.all?(items, &(validate_schema(&1) == :ok)), do: :ok, else: :error
  end

  defp validate_schema_items(%{@schema_items_key => _items}), do: :error
  defp validate_schema_items(_schema), do: :ok

  defp validate_schema_combinators(schema) do
    @schema_combinator_keys
    |> Enum.reduce_while(:ok, fn key, :ok ->
      case Map.get(schema, key) do
        nil ->
          {:cont, :ok}

        schemas when is_list(schemas) ->
          if Enum.all?(schemas, &(validate_schema(&1) == :ok)), do: {:cont, :ok}, else: {:halt, :error}

        _schemas ->
          {:halt, :error}
      end
    end)
  end

  defp validate_additional_properties(%{@schema_additional_properties_key => value}) when is_boolean(value), do: :ok

  defp validate_additional_properties(%{@schema_additional_properties_key => value}) when is_map(value),
    do: validate_schema(value)

  defp validate_additional_properties(%{@schema_additional_properties_key => _value}), do: :error
  defp validate_additional_properties(_schema), do: :ok

  defp json_encodable(%_{} = _value), do: :error

  defp json_encodable(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, normalized_key} <- json_key(key),
           {:ok, normalized_value} <- json_encodable(value) do
        {:cont, {:ok, Map.put(acc, normalized_key, normalized_value)}}
      else
        :error -> {:halt, :error}
      end
    end)
  end

  defp json_encodable(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case json_encodable(value) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end

  defp json_encodable(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
    do: {:ok, value}

  defp json_encodable(_value), do: :error

  defp json_key(key) when is_binary(key) and key != "", do: {:ok, key}
  defp json_key(_key), do: :error
end
