defmodule SymphonyElixir.Workflow.Lifecycle do
  @moduledoc """
  Shared lifecycle semantics for workflow state handling.

  This module owns tracker-neutral lifecycle phases and the behavior categories
  Symphony derives from them. Trackers should map their raw project states into
  these phases through workflow configuration.
  """

  @backlog "backlog"
  @todo "todo"
  @in_progress "in_progress"
  @human_review "human_review"
  @merging "merging"
  @rework "rework"
  @done "done"
  @canceled "canceled"
  @unknown "unknown"

  @phases [@backlog, @todo, @in_progress, @human_review, @merging, @rework, @done, @canceled, @unknown]
  @dispatch_blocker_phases [@todo, @in_progress, @merging, @rework]
  @human_review_phases [@human_review]
  @merge_phases [@merging]
  @terminal_phases [@done, @canceled]
  @phase_set @phases

  @spec phases() :: [String.t()]
  def phases, do: @phases

  @spec backlog() :: String.t()
  def backlog, do: @backlog

  @spec todo() :: String.t()
  def todo, do: @todo

  @spec in_progress() :: String.t()
  def in_progress, do: @in_progress

  @spec human_review() :: String.t()
  def human_review, do: @human_review

  @spec merging() :: String.t()
  def merging, do: @merging

  @spec rework() :: String.t()
  def rework, do: @rework

  @spec done() :: String.t()
  def done, do: @done

  @spec canceled() :: String.t()
  def canceled, do: @canceled

  @spec unknown() :: String.t()
  def unknown, do: @unknown

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
    phase_member?(phase_name, @phase_set)
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
    phase_member?(phase_name, @dispatch_blocker_phases)
  end

  @spec human_review_phase?(term()) :: boolean()
  def human_review_phase?(phase_name) do
    phase_member?(phase_name, @human_review_phases)
  end

  @spec merge_phase?(term()) :: boolean()
  def merge_phase?(phase_name) do
    phase_member?(phase_name, @merge_phases)
  end

  @spec terminal_phase?(term()) :: boolean()
  def terminal_phase?(phase_name) do
    phase_member?(phase_name, @terminal_phases)
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
        phase ->
          if dispatch_blocker_phase?(phase) do
            {:cont, :ok}
          else
            {:halt, {:error, {:invalid_tracker_state_phase_map, {:invalid_active_phase, state_name, phase}}}}
          end
      end
    end)
  end

  defp validate_terminal_state_phases(state_names, state_phase_map)
       when is_list(state_names) and is_map(state_phase_map) do
    Enum.reduce_while(state_names, :ok, fn state_name, :ok ->
      case phase_for_state(state_name, state_phase_map) do
        phase ->
          if terminal_phase?(phase) do
            {:cont, :ok}
          else
            {:halt, {:error, {:invalid_tracker_state_phase_map, {:invalid_terminal_phase, state_name, phase}}}}
          end
      end
    end)
  end

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil

  defp phase_member?(phase_name, phase_set) do
    phase_name
    |> normalize_phase()
    |> then(&Enum.member?(phase_set, &1))
  end
end
