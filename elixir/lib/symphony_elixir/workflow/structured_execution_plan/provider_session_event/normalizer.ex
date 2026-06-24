defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Normalizer do
  @moduledoc """
  Normalizes raw provider-native session payloads into canonical events.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Identifiers
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Sanitizer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Validator
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Values

  @max_tasks 50

  @type normalized_event :: map()

  @spec normalize(map(), keyword()) :: {:ok, normalized_event()} | {:error, map()}
  def normalize(event, opts \\ [])

  def normalize(event, opts) when is_map(event) and is_list(opts) do
    normalized =
      %{
        Contract.schema_key() => Contract.schema_id(),
        Contract.authority_key() => Values.authority(),
        Contract.trust_class_key() => Values.normalize_trust_class(RawInput.trust_class(event)),
        Contract.provider_kind_key() => RawInput.provider_kind(event, opts),
        Contract.surface_key() => surface(event),
        Contract.event_id_key() => RawInput.event_id(event) || Identifiers.fallback_event_id(event),
        Contract.run_id_key() => RawInput.run_id(event, opts),
        Contract.observed_at_key() => RawInput.observed_at(event, opts),
        Contract.tasks_key() => tasks(event),
        Contract.hook_observation_key() => hook_observation(event),
        Contract.warnings_key() => Values.warnings(completed_task?(event))
      }
      |> Sanitizer.compact()

    Validator.validate(normalized)
  end

  def normalize(_event, _opts) do
    {:error, %{code: ErrorCodes.invalid_event(), message: "Provider session event must be an object."}}
  end

  defp surface(event) do
    raw_surface =
      RawInput.surface(event) ||
        cond do
          RawInput.hook_present?(event) -> Values.hook_observation_surface()
          RawInput.task_values(event) != [] -> Values.provider_session_tasks_surface()
          true -> nil
        end

    Values.normalize_surface(raw_surface)
  end

  defp tasks(event) do
    event
    |> RawInput.task_values()
    |> Enum.take(@max_tasks)
    |> Enum.with_index()
    |> Enum.flat_map(fn {task, index} -> normalize_task(task, index) end)
  end

  defp normalize_task(task, index) when is_map(task) do
    [
      %{
        Contract.provider_task_id_key() => task |> RawInput.task_id() |> Kernel.||(Identifiers.generated_task_id(index)) |> Sanitizer.bounded_string(),
        Contract.title_key() => task |> RawInput.task_title() |> Sanitizer.bounded_string(),
        Contract.requested_status_key() => task |> RawInput.task_status() |> Values.normalize_status(),
        Contract.note_key() => task |> RawInput.task_note() |> Sanitizer.bounded_string(),
        Contract.correlation_key() => %{
          Contract.provider_position_key() => index,
          Contract.provider_surface_key() => Values.provider_session_tasks_surface()
        }
      }
      |> Sanitizer.compact()
    ]
  end

  defp normalize_task(task, index) when is_binary(task) do
    [
      %{
        Contract.provider_task_id_key() => Identifiers.generated_task_id(index),
        Contract.title_key() => Sanitizer.bounded_string(task),
        Contract.requested_status_key() => Values.unknown_status(),
        Contract.correlation_key() => %{
          Contract.provider_position_key() => index,
          Contract.provider_surface_key() => Values.provider_session_tasks_surface()
        }
      }
    ]
  end

  defp normalize_task(_task, _index), do: []

  defp hook_observation(event) do
    hook_source = RawInput.hook_source(event)

    if surface(event) == Values.hook_observation_surface() or is_map(hook_source) do
      hook = if is_map(hook_source), do: hook_source, else: event

      %{
        Contract.hook_name_key() => hook |> RawInput.hook_name() |> Sanitizer.bounded_string(),
        Contract.phase_key() => hook |> RawInput.hook_phase() |> Sanitizer.bounded_string(),
        Contract.status_key() => hook |> RawInput.hook_status() |> Values.normalize_status(),
        Contract.summary_key() => event |> RawInput.payload() |> Sanitizer.payload_summary()
      }
      |> Sanitizer.compact()
    end
  end

  defp completed_task?(event) do
    event
    |> RawInput.task_values()
    |> Enum.any?(fn
      task when is_map(task) -> task |> RawInput.task_status() |> Values.normalize_status() == Values.complete_status()
      _task -> false
    end)
  end
end
