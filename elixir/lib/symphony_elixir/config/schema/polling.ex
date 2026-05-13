defmodule SymphonyElixir.Config.Schema.Polling do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:interval_ms, :integer, default: 30_000)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:interval_ms], empty_values: [])
    |> validate_number(:interval_ms, greater_than: 0)
  end
end
