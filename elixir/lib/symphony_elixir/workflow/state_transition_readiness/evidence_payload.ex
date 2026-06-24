defmodule SymphonyElixir.Workflow.StateTransitionReadiness.EvidencePayload do
  @moduledoc """
  Workflow-readiness evidence payloads emitted by typed workflow tools.
  """

  @key "evidence"
  @schema "symphony.typed_tool.evidence.v1"

  @spec key() :: String.t()
  def key, do: @key

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec attach(map(), map() | nil) :: map()
  def attach(payload, evidence) when is_map(payload) and is_map(evidence), do: Map.put(payload, @key, evidence)
  def attach(payload, _evidence) when is_map(payload), do: payload

  @spec fetch(map()) :: map() | nil
  def fetch(%{@key => %{"schema" => @schema} = evidence}), do: evidence
  def fetch(_payload), do: nil
end
