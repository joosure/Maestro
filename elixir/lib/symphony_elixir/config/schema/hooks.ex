defmodule SymphonyElixir.Config.Schema.Hooks do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:after_create, :string)
    field(:before_run, :string)
    field(:after_run, :string)
    field(:before_remove, :string)
    field(:timeout_ms, :integer, default: 60_000)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:after_create, :before_run, :after_run, :before_remove, :timeout_ms], empty_values: [])
    |> validate_number(:timeout_ms, greater_than: 0)
  end
end
