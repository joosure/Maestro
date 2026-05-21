defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Contract.Envelope do
  @moduledoc """
  Stable envelope keys shared by all state-transition readiness payloads.
  """

  @schema_key "schema"
  @policy_id_key "policy_id"
  @observations_key "observations"
  @declarations_key "declarations"
  @metadata_key "metadata"

  @spec schema_key() :: String.t()
  def schema_key, do: @schema_key

  @spec policy_id_key() :: String.t()
  def policy_id_key, do: @policy_id_key

  @spec observations_key() :: String.t()
  def observations_key, do: @observations_key

  @spec declarations_key() :: String.t()
  def declarations_key, do: @declarations_key

  @spec metadata_key() :: String.t()
  def metadata_key, do: @metadata_key
end
