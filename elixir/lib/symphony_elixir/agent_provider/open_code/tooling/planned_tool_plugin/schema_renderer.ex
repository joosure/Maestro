defmodule SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin.SchemaRenderer do
  @moduledoc false

  @spec args_source(map()) :: String.t()
  def args_source(tool_spec) when is_map(tool_spec) do
    schema = Map.get(tool_spec, "inputSchema") || Map.get(tool_spec, :inputSchema) || %{}
    properties = Map.get(schema, "properties") || Map.get(schema, :properties) || %{}
    required = Map.get(schema, "required") || Map.get(schema, :required) || []

    properties
    |> Enum.sort_by(fn {name, _property_schema} -> to_string(name) end)
    |> Enum.map_join("\n", fn {name, property_schema} ->
      key = to_string(name)
      zod = zod_source(property_schema, key in required)
      "    #{Jason.encode!(key)}: #{zod},"
    end)
  end

  defp zod_source(property_schema, required?) when is_map(property_schema) do
    type = Map.get(property_schema, "type") || Map.get(property_schema, :type)
    enum = Map.get(property_schema, "enum") || Map.get(property_schema, :enum)

    base =
      cond do
        string_enum?(enum) ->
          enum
          |> Enum.filter(&is_binary/1)
          |> Jason.encode!()
          |> then(&"z.enum(#{&1})")

        nullable_object?(type) ->
          "z.record(z.string(), z.unknown()).nullable()"

        object?(type) ->
          "z.record(z.string(), z.unknown())"

        string?(type) ->
          "z.string()"

        boolean?(type) ->
          "z.boolean()"

        number?(type) ->
          "z.number()"

        true ->
          "z.unknown()"
      end
      |> maybe_nullable(nullable?(type, enum))

    maybe_optional(base, required?)
  end

  defp zod_source(_property_schema, required?), do: maybe_optional("z.unknown()", required?)

  defp string_enum?(enum) when is_list(enum), do: Enum.any?(enum, &is_binary/1)
  defp string_enum?(_enum), do: false

  defp nullable?(type, enum), do: list_type?(type, "null") or (is_list(enum) and nil in enum)

  defp maybe_nullable(source, true), do: source <> ".nullable()"
  defp maybe_nullable(source, false), do: source

  defp nullable_object?(type), do: list_type?(type, "object") and list_type?(type, "null")
  defp object?(type), do: type == "object" or list_type?(type, "object")
  defp string?(type), do: type == "string" or list_type?(type, "string")
  defp boolean?(type), do: type == "boolean" or list_type?(type, "boolean")
  defp number?(type), do: type in ["number", "integer"] or list_type?(type, "number") or list_type?(type, "integer")

  defp list_type?(types, type) when is_list(types), do: type in types
  defp list_type?(_types, _type), do: false

  defp maybe_optional(source, true), do: source
  defp maybe_optional(source, false), do: source <> ".optional()"
end
