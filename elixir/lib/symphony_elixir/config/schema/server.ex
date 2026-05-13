defmodule SymphonyElixir.Config.Schema.Server do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:port, :integer)
    field(:host, :string, default: "127.0.0.1")
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:port, :host], empty_values: [])
    |> validate_number(:port, greater_than_or_equal_to: 0)
  end
end
