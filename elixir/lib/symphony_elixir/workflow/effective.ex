defmodule SymphonyElixir.Workflow.Effective do
  @moduledoc """
  Resolved workflow contract consumed by orchestrator, prompt, and adapters.
  """

  @enforce_keys [
    :workitem_type_id,
    :active_states,
    :terminal_states,
    :state_phase_map,
    :raw_state_by_route_key,
    :policy_by_route_key,
    :profile,
    :profile_kind,
    :profile_version,
    :profile_options,
    :allowed_execution_profiles,
    :completion_contract,
    :required_capabilities,
    :optional_capabilities
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          workitem_type_id: String.t() | nil,
          active_states: [String.t()],
          terminal_states: [String.t()],
          state_phase_map: map(),
          raw_state_by_route_key: map(),
          policy_by_route_key: map(),
          profile: map(),
          profile_kind: String.t(),
          profile_version: pos_integer(),
          profile_options: map(),
          allowed_execution_profiles: [String.t()],
          completion_contract: map(),
          required_capabilities: [String.t()],
          optional_capabilities: [String.t()]
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    struct!(__MODULE__, attrs)
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = effective), do: Map.from_struct(effective)

  @spec fetch(t(), atom() | String.t()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = effective, key) do
    effective
    |> to_map()
    |> Map.fetch(normalize_key(key))
  end

  @spec get_and_update(t(), atom() | String.t(), (term() -> {term(), term()} | :pop)) ::
          {term(), t()}
  def get_and_update(%__MODULE__{} = effective, key, fun) when is_function(fun, 1) do
    normalized_key = normalize_key(key)
    current_value = Map.get(effective, normalized_key)

    case fun.(current_value) do
      {get_value, updated_value} ->
        {get_value, struct!(effective, %{normalized_key => updated_value})}

      :pop ->
        pop(effective, normalized_key)
    end
  end

  @spec pop(t(), atom() | String.t()) :: {term(), t()}
  def pop(%__MODULE__{} = effective, key) do
    normalized_key = normalize_key(key)

    {
      Map.get(effective, normalized_key),
      struct!(effective, %{normalized_key => nil})
    }
  end

  defp normalize_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp normalize_key(key), do: key
end
