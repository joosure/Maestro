defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Identifiers do
  @moduledoc """
  Derived provider-session event identifier contract.
  """

  alias SymphonyElixir.Observability.Redaction

  @fallback_event_id_prefix "provider-session-"
  @generated_task_id_prefix "provider-task-"

  @spec fallback_event_id_prefix() :: String.t()
  def fallback_event_id_prefix, do: @fallback_event_id_prefix

  @spec generated_task_id_prefix() :: String.t()
  def generated_task_id_prefix, do: @generated_task_id_prefix

  @spec fallback_event_id(map()) :: String.t()
  def fallback_event_id(event) when is_map(event) do
    @fallback_event_id_prefix <> (event |> Redaction.redact() |> :erlang.term_to_binary() |> sha256())
  end

  @spec generated_task_id(non_neg_integer()) :: String.t()
  def generated_task_id(index), do: @generated_task_id_prefix <> Integer.to_string(index + 1)

  defp sha256(value) do
    :crypto.hash(:sha256, value)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 24)
  end
end
