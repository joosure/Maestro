defmodule SymphonyElixir.Config.Schema.Observability do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:dashboard_enabled, :boolean, default: true)
    field(:refresh_ms, :integer, default: 1_000)
    field(:render_interval_ms, :integer, default: 16)
    field(:file_enabled, :boolean, default: true)
    field(:console_enabled, :boolean, default: false)
    field(:log_format, :string, default: "json")
    field(:summary_max_bytes, :integer, default: 512)
    field(:global_event_limit, :integer, default: 1_000)
    field(:issue_event_limit, :integer, default: 50)
    field(:run_event_limit, :integer, default: 200)
    field(:session_event_limit, :integer, default: 200)
    field(:index_key_limit, :integer, default: 500)
    field(:pending_event_queue_limit, :integer, default: 5_000)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :dashboard_enabled,
        :refresh_ms,
        :render_interval_ms,
        :file_enabled,
        :console_enabled,
        :log_format,
        :summary_max_bytes,
        :global_event_limit,
        :issue_event_limit,
        :run_event_limit,
        :session_event_limit,
        :index_key_limit,
        :pending_event_queue_limit
      ],
      empty_values: []
    )
    |> validate_number(:refresh_ms, greater_than: 0)
    |> validate_number(:render_interval_ms, greater_than: 0)
    |> validate_number(:summary_max_bytes, greater_than: 0)
    |> validate_number(:global_event_limit, greater_than: 0)
    |> validate_number(:issue_event_limit, greater_than: 0)
    |> validate_number(:run_event_limit, greater_than: 0)
    |> validate_number(:session_event_limit, greater_than: 0)
    |> validate_number(:index_key_limit, greater_than: 0)
    |> validate_number(:pending_event_queue_limit, greater_than: 0)
    |> validate_inclusion(:log_format, ["text", "json"])
  end
end
