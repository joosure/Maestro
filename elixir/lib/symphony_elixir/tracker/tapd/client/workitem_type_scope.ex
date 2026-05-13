defmodule SymphonyElixir.Tracker.Tapd.Client.WorkitemTypeScope do
  @moduledoc false

  alias SymphonyElixir.Tracker.Config, as: TrackerConfig
  alias SymphonyElixir.Tracker.Tapd.Client.{Fields, Request, Response}
  alias SymphonyElixir.Tracker.Tapd.WorkflowConfig

  @spec resolve([map()], map()) :: {:ok, [map()], [String.t()]}
  def resolve(raw_stories, tracker) when is_list(raw_stories) and is_map(tracker) do
    configured_workitem_type_ids = WorkflowConfig.configured_workitem_type_ids(tracker)

    filtered_stories =
      case configured_workitem_type_ids do
        [] ->
          raw_stories

        workitem_type_ids ->
          allowed_workitem_type_ids = MapSet.new(workitem_type_ids)

          Enum.filter(raw_stories, fn story ->
            story
            |> Fields.string_field("workitem_type_id")
            |> Fields.normalize_string()
            |> then(&MapSet.member?(allowed_workitem_type_ids, &1))
          end)
      end

    observed_workitem_type_ids =
      filtered_stories
      |> Enum.map(&Fields.normalize_string(Fields.string_field(&1, "workitem_type_id")))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {:ok, filtered_stories, observed_workitem_type_ids}
  end

  @spec maybe_validate([String.t()], map(), function(), boolean()) :: :ok | {:error, term()}
  def maybe_validate(_observed_workitem_type_ids, _tracker, _request_fun, false), do: :ok

  def maybe_validate(observed_workitem_type_ids, tracker, request_fun, true) do
    observed_workitem_type_ids
    |> workitem_type_ids_to_validate(tracker)
    |> validate_filtered_workitem_types(tracker, request_fun)
  end

  @spec merge_ids([String.t()], [String.t()]) :: [String.t()]
  def merge_ids(existing_workitem_type_ids, new_workitem_type_ids) do
    Enum.uniq(existing_workitem_type_ids ++ new_workitem_type_ids)
  end

  defp validate_filtered_workitem_types([], _tracker, _request_fun), do: :ok

  defp validate_filtered_workitem_types(workitem_type_ids, tracker, request_fun) do
    with {:ok, last_statuses_by_type} <-
           fetch_last_steps_by_type(workitem_type_ids, "status", tracker, request_fun),
         {:ok, last_steps_by_type} <-
           fetch_last_steps_by_type(workitem_type_ids, "step", tracker, request_fun),
         :ok <- ensure_serial_workitem_types(workitem_type_ids, last_steps_by_type),
         :ok <-
           ensure_terminal_states_match_config(workitem_type_ids, tracker, last_statuses_by_type) do
      :ok
    end
  end

  defp fetch_last_steps_by_type(workitem_type_ids, type, tracker, request_fun)
       when is_list(workitem_type_ids) and is_binary(type) do
    Enum.reduce_while(workitem_type_ids, {:ok, %{}}, fn workitem_type_id, {:ok, acc} ->
      case fetch_workitem_type_last_steps(workitem_type_id, type, tracker, request_fun) do
        {:ok, last_steps} -> {:cont, {:ok, Map.put(acc, workitem_type_id, last_steps)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_workitem_type_last_steps(workitem_type_id, type, tracker, request_fun) do
    params = %{"workitem_type_id" => workitem_type_id, "type" => type, "system" => "story"}

    with {:ok, body} <-
           Request.request("GET", "/workflows/last_steps", params,
             tracker: tracker,
             request_fun: request_fun
           ),
         {:ok, data} <- Response.decode_success_envelope("/workflows/last_steps", body),
         {:ok, last_steps} <- decode_last_steps(data, type, body) do
      {:ok, last_steps}
    else
      {:error, reason} ->
        {:error, {:tapd_workflow_lookup_failed, workitem_type_id, type, reason}}
    end
  end

  defp decode_last_steps(%{} = data, _type, _body) do
    normalized_data = Fields.normalize_keys_to_strings(data)
    {:ok, Map.keys(normalized_data) |> Enum.map(&Fields.normalize_string/1) |> Enum.reject(&is_nil/1)}
  end

  defp decode_last_steps([], _type, _body), do: {:ok, []}

  defp decode_last_steps(data, type, body) when is_list(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case decode_last_step_entry(entry, type) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        :error -> {:halt, {:error, {:unexpected_tapd_payload, "/workflows/last_steps", body}}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp decode_last_steps(_data, _type, body),
    do: {:error, {:unexpected_tapd_payload, "/workflows/last_steps", body}}

  defp decode_last_step_entry(%{"WorkflowStep" => %{} = step}, type),
    do: decode_last_step_entry(step, type)

  defp decode_last_step_entry(%{WorkflowStep: %{} = step}, type),
    do: decode_last_step_entry(step, type)

  defp decode_last_step_entry(%{} = step, "status") do
    step
    |> Fields.string_field("status")
    |> Kernel.||(Fields.string_field(step, "name"))
    |> normalize_last_step_value()
  end

  defp decode_last_step_entry(%{} = step, "step") do
    step
    |> Fields.string_field("id")
    |> Kernel.||(Fields.string_field(step, "name"))
    |> normalize_last_step_value()
  end

  defp decode_last_step_entry(_entry, _type), do: :error

  defp ensure_serial_workitem_types(workitem_type_ids, last_steps_by_type) do
    parallel_workitem_type_ids =
      workitem_type_ids
      |> Enum.filter(fn workitem_type_id ->
        case Map.get(last_steps_by_type, workitem_type_id, []) do
          [] -> false
          _step_nodes -> true
        end
      end)

    case parallel_workitem_type_ids do
      [] ->
        :ok

      _ ->
        {:error,
         {:tapd_parallel_workitem_workflow,
          %{
            workitem_type_ids: workitem_type_ids,
            parallel_workitem_type_ids: parallel_workitem_type_ids
          }}}
    end
  end

  defp ensure_terminal_states_match_config(workitem_type_ids, tracker, last_statuses_by_type) do
    terminal_state_mismatch_type_ids =
      workitem_type_ids
      |> Enum.filter(fn workitem_type_id ->
        configured_terminal_states =
          configured_terminal_states_for_workitem_type(tracker, workitem_type_id)
          |> MapSet.new()

        last_statuses_by_type
        |> Map.get(workitem_type_id, [])
        |> Enum.map(&Fields.normalize_string/1)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()
        |> MapSet.equal?(configured_terminal_states)
        |> Kernel.not()
      end)

    case terminal_state_mismatch_type_ids do
      [] ->
        :ok

      _ ->
        details =
          %{
            workitem_type_ids: workitem_type_ids,
            configured_terminal_states_by_type:
              Map.new(workitem_type_ids, fn workitem_type_id ->
                {workitem_type_id, configured_terminal_states_for_workitem_type(tracker, workitem_type_id)}
              end),
            terminal_states_by_type: last_statuses_by_type
          }
          |> Map.put(terminal_state_mismatch_key(), terminal_state_mismatch_type_ids)

        {:error, {terminal_state_mismatch_code(), details}}
    end
  end

  defp workitem_type_ids_to_validate(observed_workitem_type_ids, tracker) do
    case WorkflowConfig.configured_workitem_type_ids(tracker) do
      [] -> observed_workitem_type_ids
      configured_workitem_type_ids -> configured_workitem_type_ids
    end
  end

  defp configured_terminal_states_for_workitem_type(tracker, workitem_type_id) do
    tracker
    |> WorkflowConfig.workflow_for_workitem_type(workitem_type_id)
    |> case do
      %{terminal_states: terminal_states} -> terminal_states
      _ -> List.wrap(TrackerConfig.terminal_states(tracker))
    end
    |> Enum.map(&Fields.normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_last_step_value(nil), do: {:ok, nil}

  defp normalize_last_step_value(value)
       when is_binary(value) or is_integer(value) or is_boolean(value) or is_float(value) do
    {:ok, Fields.normalize_string(value)}
  end

  defp normalize_last_step_value(value) when is_atom(value) do
    {:ok, Atom.to_string(value)}
  end

  defp normalize_last_step_value(_value), do: :error

  defp terminal_state_mismatch_code, do: :tapd_mismatched_workitem_type_ids

  defp terminal_state_mismatch_key, do: :mismatched_workitem_type_ids
end
