defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.ActiveKey do
  @moduledoc """
  Canonical active route/profile lookup key for workflow execution-plan storage.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields

  @spec active?(map()) :: boolean()
  def active?(envelope) when is_map(envelope), do: Map.get(envelope, Fields.status()) == Contract.active_plan_status()
  def active?(_envelope), do: false

  @spec from_envelope!(map()) :: {String.t(), String.t(), pos_integer(), String.t()}
  def from_envelope!(envelope) when is_map(envelope) do
    workflow_profile = Map.fetch!(envelope, Fields.workflow_profile())

    {
      Map.fetch!(envelope, Fields.run_id()),
      Map.fetch!(workflow_profile, Fields.profile_kind()),
      Map.fetch!(workflow_profile, Fields.profile_version()),
      Map.fetch!(envelope, Fields.route_key())
    }
  end

  @spec encode({String.t(), String.t(), pos_integer(), String.t()}) :: String.t()
  def encode({run_id, profile_kind, profile_version, route_key}) do
    [run_id, profile_kind, Integer.to_string(profile_version), route_key]
    |> Enum.map_join("/", &URI.encode_www_form/1)
  end
end
