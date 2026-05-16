defmodule SymphonyElixir.Orchestrator.Dispatch.Context do
  @moduledoc false

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @type t :: %{
          active_state_names: [String.t()],
          terminal_state_names: [String.t()],
          state_phase_map: map(),
          workflow_settings: map(),
          available_capabilities: MapSet.t(String.t()),
          max_concurrent_agents_for_state: (term() -> pos_integer()) | nil
        }

  @spec new(term(), term(), keyword()) :: t()
  def new(active_states, terminal_states, opts \\ []) do
    %{
      active_state_names: normalized_state_names(active_states),
      terminal_state_names: normalized_state_names(terminal_states),
      state_phase_map:
        opts
        |> Keyword.get(:state_phase_map, %{})
        |> WorkflowLifecycle.normalize_state_phase_map(),
      workflow_settings: Keyword.get(opts, :workflow_settings, %{}),
      available_capabilities:
        opts
        |> Keyword.get(:available_capabilities, [])
        |> normalize_capabilities(),
      max_concurrent_agents_for_state: Keyword.get(opts, :max_concurrent_agents_for_state)
    }
  end

  @spec normalized_state_names(term()) :: [String.t()]
  def normalized_state_names(states) do
    states
    |> normalize_state_set()
    |> Enum.to_list()
  end

  @spec state_phase_map(map()) :: map()
  def state_phase_map(%{state_phase_map: state_phase_map}) when is_map(state_phase_map), do: state_phase_map
  def state_phase_map(_context), do: %{}

  @spec workflow_settings(map()) :: map()
  def workflow_settings(%{workflow_settings: workflow_settings}) when is_map(workflow_settings), do: workflow_settings
  def workflow_settings(_context), do: %{}

  @spec available_capabilities(map()) :: MapSet.t(String.t())
  def available_capabilities(%{available_capabilities: %MapSet{} = available_capabilities}), do: available_capabilities
  def available_capabilities(_context), do: MapSet.new()

  defp normalize_state_set(%MapSet{} = states) do
    states
    |> Enum.map(&WorkflowLifecycle.normalize_tracker_state/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalize_state_set(states) when is_list(states) do
    states
    |> Enum.map(&WorkflowLifecycle.normalize_tracker_state/1)
    |> Enum.reject(&(&1 == ""))
    |> MapSet.new()
  end

  defp normalize_state_set(_states), do: MapSet.new()

  defp normalize_capabilities(%MapSet{} = capabilities), do: capabilities

  defp normalize_capabilities(capabilities) do
    capabilities
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end
end
