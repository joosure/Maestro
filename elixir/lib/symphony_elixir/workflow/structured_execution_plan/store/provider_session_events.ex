defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ProviderSessionEvents do
  @moduledoc """
  Store policy for non-authoritative provider session events.

  Provider session events are immutable diagnostic/projection records stored in
  workflow plan extensions. They are not evidence refs and do not satisfy
  readiness requirements.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract, as: ProviderEventContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.ErrorCodes
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Record

  @default_event_limit 50

  @spec record(map(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  def record(plan, event, opts) when is_map(plan) and is_map(event) and is_list(opts) do
    extension_key = ProviderSessionEvent.extension_key()
    extensions = Map.get(plan, Fields.extensions(), %{})
    events = provider_session_events(extensions, extension_key)

    case Enum.find(events, &(Map.get(&1, ProviderEventContract.event_id_key()) == Map.get(event, ProviderEventContract.event_id_key()))) do
      nil ->
        updated_extensions =
          Map.put(extensions, extension_key, Enum.take([event | events], event_limit(opts)))

        {:ok,
         plan
         |> Record.bump_plan(opts)
         |> Map.put(Fields.extensions(), updated_extensions)}

      ^event ->
        {:ok, plan}

      _existing_event ->
        {:error,
         %{
           code: ErrorCodes.provider_session_event_conflict(),
           message: "Provider session events are immutable once recorded.",
           event_id: Map.get(event, ProviderEventContract.event_id_key())
         }}
    end
  end

  defp provider_session_events(extensions, extension_key) when is_map(extensions) do
    case Map.get(extensions, extension_key) do
      events when is_list(events) -> events
      _events -> []
    end
  end

  defp event_limit(opts) do
    opts
    |> Keyword.get(:provider_session_event_limit, @default_event_limit)
    |> positive_integer(@default_event_limit)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
