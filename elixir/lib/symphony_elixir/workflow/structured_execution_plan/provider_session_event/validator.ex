defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Validator do
  @moduledoc """
  Validates canonical provider-session events.

  This validator intentionally consumes only normalized string-keyed events.
  Raw provider aliases and atom-keyed input belong to `ProviderSessionEvent.RawInput`.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Values

  @type normalized_event :: map()

  @spec validate(map()) :: {:ok, normalized_event()} | {:error, map()}
  def validate(event) when is_map(event) do
    errors =
      []
      |> collect_required_keys(event)
      |> collect_unknown_event_keys(event)
      |> collect_literal(event, Contract.schema_key(), Contract.schema_id())
      |> collect_literal(event, Contract.authority_key(), Values.authority())
      |> collect_string(event, Contract.provider_kind_key())
      |> collect_surface(event)
      |> collect_string(event, Contract.event_id_key())
      |> collect_optional_string(event, Contract.run_id_key())
      |> collect_string(event, Contract.observed_at_key())
      |> collect_tasks(event)
      |> collect_hook_observation(event)

    if errors == [] do
      {:ok, event}
    else
      {:error, %{code: ErrorCodes.invalid_event(), message: "Provider session event is invalid.", errors: errors}}
    end
  end

  def validate(_event) do
    {:error, %{code: ErrorCodes.invalid_event(), message: "Provider session event must be an object."}}
  end

  defp collect_required_keys(errors, event) do
    missing =
      Contract.required_event_keys()
      |> Enum.reject(fn key -> present?(Map.get(event, key)) end)
      |> Enum.map(&%{code: ErrorCodes.missing_required_field(), path: [&1], message: "Required provider session event field is missing."})

    errors ++ missing
  end

  defp collect_unknown_event_keys(errors, event) do
    unknown =
      event
      |> Map.keys()
      |> Enum.reject(&(&1 in Contract.allowed_event_keys()))
      |> Enum.map(&%{code: ErrorCodes.unknown_field(), path: [&1], message: "Provider session event field is not supported."})

    errors ++ unknown
  end

  defp collect_literal(errors, event, key, expected) do
    if Map.get(event, key) == expected do
      errors
    else
      errors ++ [%{code: ErrorCodes.invalid_value(), path: [key], message: "Provider session event field has an unsupported value."}]
    end
  end

  defp collect_string(errors, event, key) do
    if non_empty_string?(Map.get(event, key)) do
      errors
    else
      errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Provider session event field must be a non-empty string."}]
    end
  end

  defp collect_optional_string(errors, event, key) do
    case Map.get(event, key) do
      nil -> errors
      value when is_binary(value) -> errors
      _value -> errors ++ [%{code: ErrorCodes.invalid_type(), path: [key], message: "Provider session event field must be a string."}]
    end
  end

  defp collect_surface(errors, event) do
    if Map.get(event, Contract.surface_key()) in Values.surfaces() do
      errors
    else
      errors ++ [%{code: ErrorCodes.invalid_enum(), path: [Contract.surface_key()], message: "Provider session event surface is unsupported."}]
    end
  end

  defp collect_tasks(errors, event) do
    case Map.fetch(event, Contract.tasks_key()) do
      {:ok, tasks} when is_list(tasks) ->
        task_errors =
          tasks
          |> Enum.with_index()
          |> Enum.flat_map(fn {task, index} -> task_errors(task, index) end)

        errors ++ task_errors

      {:ok, _tasks} ->
        errors ++ [%{code: ErrorCodes.invalid_type(), path: [Contract.tasks_key()], message: "Provider session event tasks must be an array."}]

      :error ->
        errors
    end
  end

  defp task_errors(task, index) when is_map(task) do
    path = [Contract.tasks_key(), index]

    task
    |> Map.keys()
    |> Enum.reject(&(&1 in Contract.allowed_task_keys()))
    |> Enum.map(&%{code: ErrorCodes.unknown_field(), path: path ++ [&1], message: "Provider session task field is not supported."})
  end

  defp task_errors(_task, index), do: [%{code: ErrorCodes.invalid_type(), path: [Contract.tasks_key(), index], message: "Provider session task must be an object."}]

  defp collect_hook_observation(errors, event) do
    case Map.fetch(event, Contract.hook_observation_key()) do
      {:ok, hook} when is_map(hook) ->
        unknown =
          hook
          |> Map.keys()
          |> Enum.reject(&(&1 in Contract.allowed_hook_keys()))
          |> Enum.map(&%{code: ErrorCodes.unknown_field(), path: [Contract.hook_observation_key(), &1], message: "Provider hook observation field is not supported."})

        errors ++ unknown

      {:ok, _hook} ->
        errors ++ [%{code: ErrorCodes.invalid_type(), path: [Contract.hook_observation_key()], message: "Provider hook observation must be an object."}]

      :error ->
        errors
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp non_empty_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_string?(_value), do: false
end
