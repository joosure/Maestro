defmodule SymphonyElixir.Config.Schema.Quota do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:preflight, :string, default: "off")
    field(:poller_enabled, :boolean, default: false)
    field(:poll_interval_ms, :integer, default: 300_000)
    field(:probe_timeout_ms, :integer, default: 15_000)
    field(:poll_providers, {:array, :string}, default: [])
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :preflight,
        :poller_enabled,
        :poll_interval_ms,
        :probe_timeout_ms,
        :poll_providers
      ],
      empty_values: []
    )
    |> validate_inclusion(:preflight, ["off", "advisory", "required"])
    |> validate_number(:poll_interval_ms, greater_than: 0)
    |> validate_number(:probe_timeout_ms, greater_than: 0)
    |> validate_poll_providers()
  end

  defp validate_poll_providers(changeset) do
    validate_change(changeset, :poll_providers, fn :poll_providers, providers ->
      if Enum.all?(providers, &(is_binary(&1) and String.trim(&1) != "")) do
        []
      else
        [poll_providers: "must be a list of non-blank strings"]
      end
    end)
  end
end
