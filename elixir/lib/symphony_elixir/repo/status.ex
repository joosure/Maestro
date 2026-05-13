defmodule SymphonyElixir.Repo.Status do
  @moduledoc """
  Provider-neutral working-tree status for a target Git repository.
  """

  alias SymphonyElixir.Repo.Error

  @states ~w(clean dirty conflicted detached missing)a

  @enforce_keys [:state, :path]
  defstruct [
    :state,
    :path,
    :root,
    :branch,
    :head_sha,
    entries: [],
    clean?: false,
    dirty?: false,
    conflicted?: false,
    detached?: false,
    missing?: false,
    error: nil
  ]

  @type state :: :clean | :dirty | :conflicted | :detached | :missing

  @type entry :: %{
          required(:status) => String.t(),
          required(:index) => String.t(),
          required(:worktree) => String.t(),
          required(:path) => Path.t(),
          optional(:original_path) => Path.t()
        }

  @type t :: %__MODULE__{
          state: state(),
          path: Path.t(),
          root: Path.t() | nil,
          branch: String.t() | nil,
          head_sha: String.t() | nil,
          entries: [entry()],
          clean?: boolean(),
          dirty?: boolean(),
          conflicted?: boolean(),
          detached?: boolean(),
          missing?: boolean(),
          error: Error.t() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    entries = Map.get(attrs, :entries, [])
    detached? = Map.get(attrs, :detached?, false)
    conflicted? = Map.get(attrs, :conflicted?, conflicted_entries?(entries))
    dirty? = entries != []
    state = state_for(Map.get(attrs, :state), dirty?, conflicted?, detached?)

    struct(__MODULE__, %{
      state: state,
      path: Map.fetch!(attrs, :path),
      root: Map.get(attrs, :root),
      branch: Map.get(attrs, :branch),
      head_sha: Map.get(attrs, :head_sha),
      entries: entries,
      clean?: state == :clean,
      dirty?: dirty?,
      conflicted?: conflicted?,
      detached?: detached?,
      missing?: false,
      error: Map.get(attrs, :error)
    })
  end

  @spec missing(Path.t(), Error.t()) :: t()
  def missing(path, %Error{} = error) when is_binary(path) do
    %__MODULE__{
      state: :missing,
      path: path,
      missing?: true,
      error: error
    }
  end

  @spec valid_state?(term()) :: boolean()
  def valid_state?(state), do: state in @states

  defp state_for(state, _dirty?, _conflicted?, _detached?) when state in @states, do: state
  defp state_for(_state, _dirty?, true, _detached?), do: :conflicted
  defp state_for(_state, _dirty?, _conflicted?, true), do: :detached
  defp state_for(_state, true, _conflicted?, _detached?), do: :dirty
  defp state_for(_state, false, _conflicted?, _detached?), do: :clean

  defp conflicted_entries?(entries) when is_list(entries) do
    Enum.any?(entries, fn
      %{status: status} -> status in ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
      _entry -> false
    end)
  end
end
