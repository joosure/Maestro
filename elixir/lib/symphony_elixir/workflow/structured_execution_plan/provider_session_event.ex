defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent do
  @moduledoc """
  Normalizes provider-native plan/todo/task surfaces into non-authoritative
  session events.

  These records are correlation and display metadata only. They are not
  evidence refs and cannot satisfy canonical structured plan item requirements.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Normalizer
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Validator

  @type normalized_event :: map()

  @spec schema_id() :: String.t()
  def schema_id, do: Contract.schema_id()

  @spec extension_key() :: String.t()
  def extension_key, do: Contract.extension_key()

  @spec normalize(map(), keyword()) :: {:ok, normalized_event()} | {:error, map()}
  defdelegate normalize(event, opts \\ []), to: Normalizer

  @spec validate(map()) :: {:ok, normalized_event()} | {:error, map()}
  defdelegate validate(event), to: Validator
end
