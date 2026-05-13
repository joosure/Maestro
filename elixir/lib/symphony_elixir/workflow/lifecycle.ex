defmodule SymphonyElixir.Workflow.Lifecycle do
  @moduledoc """
  Shared lifecycle semantics for workflow state handling.
  """

  @phases ~w[backlog todo in_progress human_review merging rework done canceled unknown]
  @dispatch_blocker_phases ~w[todo in_progress merging rework]
  @active_execution_phases MapSet.new(@dispatch_blocker_phases)
  @terminal_phases MapSet.new(~w[done canceled])

  @spec phases() :: [String.t()]
  def phases, do: @phases

  @spec normalize_tracker_state(term()) :: String.t()
  def normalize_tracker_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  def normalize_tracker_state(state_name) when is_atom(state_name) do
    state_name
    |> Atom.to_string()
    |> normalize_tracker_state()
  end

  def normalize_tracker_state(state_name) do
    state_name
    |> to_string()
    |> normalize_tracker_state()
  end

  @spec normalize_phase(term()) :: String.t() | nil
  def normalize_phase(nil), do: nil

  def normalize_phase(phase_name) when is_binary(phase_name) do
    case String.trim(phase_name) do
      "" ->
        nil

      trimmed ->
        trimmed
        |> String.downcase()
        |> String.replace(~r/[\s-]+/, "_")
    end
  end

  def normalize_phase(phase_name) when is_atom(phase_name) do
    phase_name
    |> Atom.to_string()
    |> normalize_phase()
  end

  def normalize_phase(_phase_name), do: nil

  @spec valid_phase?(term()) :: boolean()
  def valid_phase?(phase_name) do
    normalized_phase = normalize_phase(phase_name)
    is_binary(normalized_phase) and normalized_phase in @phases
  end

  @spec normalize_state_phase_map(nil | map()) :: map()
  def normalize_state_phase_map(nil), do: %{}

  def normalize_state_phase_map(state_phase_map) when is_map(state_phase_map) do
    Enum.reduce(state_phase_map, %{}, fn {state_name, phase_name}, acc ->
      normalized_state = normalize_tracker_state(state_name)
      normalized_phase = normalize_phase(phase_name)

      if normalized_state == "" do
        acc
      else
        Map.put(acc, normalized_state, normalized_phase)
      end
    end)
  end

  @spec phase_for_state(term(), map() | nil) :: String.t() | nil
  def phase_for_state(state_name, state_phase_map) when is_map(state_phase_map) do
    case normalize_tracker_state(state_name) do
      "" ->
        nil

      normalized_state ->
        Map.get(state_phase_map, normalized_state) ||
          state_phase_map
          |> normalize_state_phase_map()
          |> Map.get(normalized_state)
    end
  end

  def phase_for_state(_state_name, _state_phase_map), do: nil

  @spec dispatch_blocker_phase?(term()) :: boolean()
  def dispatch_blocker_phase?(phase_name) do
    phase_name
    |> normalize_phase()
    |> then(&MapSet.member?(@active_execution_phases, &1))
  end

  @spec terminal_phase?(term()) :: boolean()
  def terminal_phase?(phase_name) do
    phase_name
    |> normalize_phase()
    |> then(&MapSet.member?(@terminal_phases, &1))
  end

  @spec validate_state_phase_map(map()) :: :ok | {:error, term()}
  def validate_state_phase_map(attrs) when is_map(attrs) do
    lifecycle = map_value(attrs, :lifecycle) || %{}
    active_states = List.wrap(map_value(attrs, :active_states) || map_value(lifecycle, :active_states))
    terminal_states = List.wrap(map_value(attrs, :terminal_states) || map_value(lifecycle, :terminal_states))
    raw_state_phase_map = map_value(attrs, :state_phase_map) || map_value(lifecycle, :state_phase_map) || %{}
    normalized_state_phase_map = normalize_state_phase_map(raw_state_phase_map)

    cond do
      map_size(normalized_state_phase_map) == 0 and (active_states != [] or terminal_states != []) ->
        {:error, :missing_tracker_state_phase_map}

      true ->
        with :ok <- validate_state_phase_entries(raw_state_phase_map),
             :ok <- validate_mapped_states(active_states, normalized_state_phase_map),
             :ok <- validate_mapped_states(terminal_states, normalized_state_phase_map),
             :ok <- validate_active_state_phases(active_states, normalized_state_phase_map),
             :ok <- validate_terminal_state_phases(terminal_states, normalized_state_phase_map) do
          :ok
        end
    end
  end

  def validate_state_phase_map(_attrs), do: {:error, :missing_tracker_state_phase_map}

  defp validate_state_phase_entries(state_phase_map) when is_map(state_phase_map) do
    Enum.reduce_while(state_phase_map, :ok, fn {state_name, phase_name}, :ok ->
      cond do
        normalize_tracker_state(state_name) == "" ->
          {:halt, {:error, {:invalid_tracker_state_phase_map, {:blank_state_name, state_name}}}}

        not valid_phase?(phase_name) ->
          {:halt, {:error, {:invalid_tracker_state_phase_map, {:invalid_phase, state_name, phase_name}}}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_mapped_states(state_names, state_phase_map) when is_list(state_names) and is_map(state_phase_map) do
    Enum.reduce_while(state_names, :ok, fn state_name, :ok ->
      case phase_for_state(state_name, state_phase_map) do
        nil ->
          {:halt, {:error, {:invalid_tracker_state_phase_map, {:missing_mapping, state_name}}}}

        _phase ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_active_state_phases(state_names, state_phase_map)
       when is_list(state_names) and is_map(state_phase_map) do
    Enum.reduce_while(state_names, :ok, fn state_name, :ok ->
      case phase_for_state(state_name, state_phase_map) do
        phase when phase in @dispatch_blocker_phases ->
          {:cont, :ok}

        phase ->
          {:halt, {:error, {:invalid_tracker_state_phase_map, {:invalid_active_phase, state_name, phase}}}}
      end
    end)
  end

  defp validate_terminal_state_phases(state_names, state_phase_map)
       when is_list(state_names) and is_map(state_phase_map) do
    Enum.reduce_while(state_names, :ok, fn state_name, :ok ->
      case phase_for_state(state_name, state_phase_map) do
        phase when phase in ~w[done canceled] ->
          {:cont, :ok}

        phase ->
          {:halt, {:error, {:invalid_tracker_state_phase_map, {:invalid_terminal_phase, state_name, phase}}}}
      end
    end)
  end

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil
end
