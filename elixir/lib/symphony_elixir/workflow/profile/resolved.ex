defmodule SymphonyElixir.Workflow.Profile.Resolved do
  @moduledoc """
  Resolved workflow profile selected for an effective workflow.
  """

  alias SymphonyElixir.Workflow.Profile.Config

  @enforce_keys [:kind, :version, :options, :module]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          kind: String.t(),
          version: pos_integer(),
          options: map(),
          module: module()
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @spec from_config(Config.t(), module()) :: t()
  def from_config(%Config{} = config, profile_module) when is_atom(profile_module) do
    new!(%{
      kind: config.kind,
      version: config.version,
      options: config.options,
      module: profile_module
    })
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = resolved), do: Map.from_struct(resolved)
end
