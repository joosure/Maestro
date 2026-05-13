defmodule SymphonyElixir.Config.Schema.Agent do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Config.Schema.{AgentExecution, Credentials, Quota}

  @primary_key false
  embedded_schema do
    embeds_one(:execution, AgentExecution, on_replace: :update, defaults_to_struct: true)
    embeds_one(:credentials, Credentials, on_replace: :update, defaults_to_struct: true)
    embeds_one(:quota, Quota, on_replace: :update, defaults_to_struct: true)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [], empty_values: [])
    |> validate_supported_keys(attrs)
    |> cast_embed(:execution, with: &AgentExecution.changeset/2)
    |> cast_embed(:credentials, with: &Credentials.changeset/2)
    |> cast_embed(:quota, with: &Quota.changeset/2)
  end

  defp validate_supported_keys(changeset, attrs) when is_map(attrs) do
    unsupported_keys =
      attrs
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 in ["execution", "credentials", "quota"]))

    case unsupported_keys do
      [] ->
        changeset

      keys ->
        add_error(
          changeset,
          :execution,
          "supports only execution, credentials, and quota under agent; unsupported keys: #{Enum.join(keys, ", ")}"
        )
    end
  end
end
