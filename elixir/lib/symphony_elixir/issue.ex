defmodule SymphonyElixir.Issue do
  @moduledoc """
  Normalized issue representation used by the orchestrator.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :lifecycle_phase,
    :workitem_type_id,
    :branch_name,
    :url,
    :assignee_id,
    blocked_by: [],
    labels: [],
    workflow: %{},
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type blocker :: map()

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          lifecycle_phase: String.t() | nil,
          workitem_type_id: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          blocked_by: [blocker()],
          labels: [String.t()],
          workflow: map(),
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}) do
    labels
  end
end
