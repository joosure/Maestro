defmodule SymphonyElixir.Workflow.Extension.Runtime.Projection do
  @moduledoc """
  Stable runtime projection exposed to workflow extensions.

  The projection intentionally contains only platform-approved facts. It does
  not expose the Orchestrator state map, so extensions cannot couple their
  domain rules to platform runtime internals.
  """

  defstruct running_issue_ids: MapSet.new(),
            claimed_issue_ids: MapSet.new(),
            running_count: 0,
            claimed_count: 0,
            available_slots: nil,
            max_concurrent_agents: nil,
            extension_states: %{}

  @type t :: %__MODULE__{
          running_issue_ids: term(),
          claimed_issue_ids: term(),
          running_count: non_neg_integer(),
          claimed_count: non_neg_integer(),
          available_slots: non_neg_integer() | nil,
          max_concurrent_agents: non_neg_integer() | nil,
          extension_states: map()
        }

  @spec new(map()) :: t()
  def new(runtime_state) when is_map(runtime_state) do
    running_issue_ids = running_issue_ids(runtime_state)
    claimed_issue_ids = claimed_issue_ids(runtime_state)
    max_concurrent_agents = integer_or_nil(Map.get(runtime_state, :max_concurrent_agents))

    %__MODULE__{
      running_issue_ids: running_issue_ids,
      claimed_issue_ids: claimed_issue_ids,
      running_count: Enum.count(running_issue_ids),
      claimed_count: Enum.count(claimed_issue_ids),
      available_slots: available_slots(max_concurrent_agents, Enum.count(running_issue_ids)),
      max_concurrent_agents: max_concurrent_agents,
      extension_states: extension_states(runtime_state)
    }
  end

  @spec running_issue?(t(), term()) :: boolean()
  def running_issue?(%__MODULE__{} = projection, issue_id) when is_binary(issue_id) do
    MapSet.member?(projection.running_issue_ids, issue_id)
  end

  def running_issue?(%__MODULE__{}, _issue_id), do: false

  @spec claimed_issue?(t(), term()) :: boolean()
  def claimed_issue?(%__MODULE__{} = projection, issue_id) when is_binary(issue_id) do
    MapSet.member?(projection.claimed_issue_ids, issue_id)
  end

  def claimed_issue?(%__MODULE__{}, _issue_id), do: false

  @spec extension_state(t(), String.t()) :: map()
  def extension_state(%__MODULE__{} = projection, extension_id) when is_binary(extension_id) do
    case Map.get(projection.extension_states, extension_id) do
      state when is_map(state) -> state
      _state -> %{}
    end
  end

  defp running_issue_ids(runtime_state) do
    runtime_state
    |> Map.get(:running, %{})
    |> case do
      running when is_map(running) -> running |> Map.keys() |> strings_to_set()
      _running -> MapSet.new()
    end
  end

  defp claimed_issue_ids(runtime_state) do
    runtime_state
    |> Map.get(:claimed, MapSet.new())
    |> case do
      %MapSet{} = claimed -> claimed |> MapSet.to_list() |> strings_to_set()
      claimed when is_list(claimed) -> strings_to_set(claimed)
      _claimed -> MapSet.new()
    end
  end

  defp strings_to_set(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp extension_states(runtime_state) do
    case Map.get(runtime_state, :workflow_extensions, %{}) do
      states when is_map(states) -> states
      _states -> %{}
    end
  end

  defp available_slots(nil, _running_count), do: nil
  defp available_slots(max_concurrent_agents, running_count), do: max(max_concurrent_agents - running_count, 0)

  defp integer_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp integer_or_nil(_value), do: nil
end
