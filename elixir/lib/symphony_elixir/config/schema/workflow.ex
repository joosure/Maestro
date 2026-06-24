defmodule SymphonyElixir.Config.Schema.Workflow do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:profile, :map, default: %{})
    field(:reconciliation, :map, default: %{})
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:profile, :reconciliation], empty_values: [])
    |> validate_profile()
    |> validate_reconciliation()
  end

  defp validate_profile(changeset) do
    profile = get_field(changeset, :profile)

    cond do
      is_nil(profile) ->
        changeset

      not is_map(profile) ->
        add_error(changeset, :profile, "must be a map")

      true ->
        changeset
        |> validate_optional_string_field(profile, "kind", :"profile.kind")
        |> validate_optional_positive_integer_field(profile, "version", :"profile.version")
        |> validate_optional_map_field(profile, "options", :"profile.options")
    end
  end

  defp validate_reconciliation(changeset) do
    reconciliation = get_field(changeset, :reconciliation)

    cond do
      is_nil(reconciliation) ->
        changeset

      not is_map(reconciliation) ->
        add_error(changeset, :reconciliation, "must be a map")

      true ->
        changeset
    end
  end

  defp validate_optional_string_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil -> changeset
      value when is_binary(value) -> changeset
      _ -> add_error(changeset, error_field, "must be a string")
    end
  end

  defp validate_optional_positive_integer_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil -> changeset
      value when is_integer(value) and value > 0 -> changeset
      _ -> add_error(changeset, error_field, "must be a positive integer")
    end
  end

  defp validate_optional_map_field(changeset, values, key, error_field)
       when is_binary(key) and is_atom(error_field) do
    case nested_value(values, key) do
      nil -> changeset
      value when is_map(value) -> changeset
      _ -> add_error(changeset, error_field, "must be a map")
    end
  end

  defp nested_value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end
end
