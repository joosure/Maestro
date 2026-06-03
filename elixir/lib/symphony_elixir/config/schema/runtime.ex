defmodule SymphonyElixir.Config.Schema.Runtime do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias SymphonyElixir.Config.Schema.Runtime.Agent

  @primary_key false
  embedded_schema do
    embeds_one(:agent, Agent, on_replace: :update, defaults_to_struct: true)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [], empty_values: [])
    |> cast_embed(:agent, with: &Agent.changeset/2)
  end
end
