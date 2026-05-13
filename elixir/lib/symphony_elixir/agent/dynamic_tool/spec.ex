defmodule SymphonyElixir.Agent.DynamicTool.Spec do
  @moduledoc """
  Normalizes provider-neutral dynamic tool specs before provider registration.
  """

  @name_pattern ~r/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/
  @default_input_schema %{"type" => "object", "additionalProperties" => true}

  @type t :: %{
          required(String.t()) => String.t() | map()
        }

  @spec normalize_many(term()) :: [t()]
  def normalize_many(tool_specs) when is_list(tool_specs) do
    {_seen, specs} =
      Enum.reduce(tool_specs, {MapSet.new(), []}, fn tool_spec, {seen, specs} ->
        case normalize(tool_spec) do
          {:ok, %{"name" => name} = normalized} ->
            if MapSet.member?(seen, name) do
              {seen, specs}
            else
              {MapSet.put(seen, name), [normalized | specs]}
            end

          :error ->
            {seen, specs}
        end
      end)

    Enum.reverse(specs)
  end

  def normalize_many(_tool_specs), do: []

  @spec normalize(term()) :: {:ok, t()} | :error
  def normalize(tool_spec) when is_map(tool_spec) do
    with {:ok, name} <- normalize_name(tool_spec),
         {:ok, description} <- normalize_description(tool_spec, name),
         {:ok, input_schema} <- normalize_input_schema(tool_spec) do
      {:ok,
       %{
         "name" => name,
         "description" => description,
         "inputSchema" => input_schema
       }}
    else
      :error -> :error
    end
  end

  def normalize(_tool_spec), do: :error

  @spec valid_name?(term()) :: boolean()
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_pattern, name)
  def valid_name?(_name), do: false

  defp normalize_name(tool_spec) do
    case string_field(tool_spec, "name") do
      name when is_binary(name) and name != "" ->
        if valid_name?(name), do: {:ok, name}, else: :error

      _name ->
        :error
    end
  end

  defp normalize_description(tool_spec, name) do
    case string_field(tool_spec, "description") do
      description when is_binary(description) and description != "" ->
        {:ok, description}

      _description ->
        {:ok, "Execute Symphony dynamic tool #{name}."}
    end
  end

  defp normalize_input_schema(tool_spec) do
    raw_schema =
      Map.get(tool_spec, "inputSchema") ||
        Map.get(tool_spec, :inputSchema) ||
        Map.get(tool_spec, "input_schema") ||
        Map.get(tool_spec, :input_schema) ||
        @default_input_schema

    with {:ok, schema} <- json_encodable(raw_schema),
         schema when is_map(schema) <- Map.put_new(schema, "type", "object"),
         "object" <- Map.get(schema, "type"),
         :ok <- validate_required(schema),
         :ok <- validate_properties(schema) do
      {:ok, schema}
    else
      _invalid -> :error
    end
  end

  defp validate_required(%{"required" => required}) when is_list(required) do
    if Enum.all?(required, &is_binary/1), do: :ok, else: :error
  end

  defp validate_required(%{"required" => _required}), do: :error
  defp validate_required(_schema), do: :ok

  defp validate_properties(%{"properties" => properties}) when is_map(properties), do: :ok
  defp validate_properties(%{"properties" => _properties}), do: :error
  defp validate_properties(_schema), do: :ok

  defp string_field(map, field) do
    value = Map.get(map, field) || Map.get(map, atom_field(field))

    case value do
      value when is_binary(value) -> String.trim(value)
      _value -> nil
    end
  end

  defp atom_field("name"), do: :name
  defp atom_field("description"), do: :description

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
  defp json_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp json_key(key) when is_integer(key), do: {:ok, Integer.to_string(key)}
  defp json_key(_key), do: :error
end
