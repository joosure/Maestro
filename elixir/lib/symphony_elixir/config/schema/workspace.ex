defmodule SymphonyElixir.Config.Schema.Workspace do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:root, :string, default: Path.join(System.tmp_dir!(), "symphony_workspaces"))
    field(:bootstrap_automation_from, :string)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:root, :bootstrap_automation_from], empty_values: [])
  end
end
