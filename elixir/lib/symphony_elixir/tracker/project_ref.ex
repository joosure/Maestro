defmodule SymphonyElixir.Tracker.ProjectRef do
  @moduledoc """
  Minimal normalized tracker project reference.

  Returned by `Tracker.project_ref/0` to give consumers a
  provider-agnostic handle for the current project:

    * `kind` — adapter identifier (mirrors `Config.kind`)
    * `id` — provider-specific project/workspace ID
    * `url` — deep-link URL to the project in the tracker UI
  """

  defstruct [:kind, :id, :url]

  @type t :: %__MODULE__{
          kind: String.t() | nil,
          id: String.t() | nil,
          url: String.t() | nil
        }
end
