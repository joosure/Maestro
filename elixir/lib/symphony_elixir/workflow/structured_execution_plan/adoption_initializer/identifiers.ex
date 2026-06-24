defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Identifiers do
  @moduledoc """
  Identifier contract for workflow structured-plan adoption initialization.
  """

  @default_plan_id_prefix "workflow-plan"
  @default_route_segment "default"

  @spec default_plan_id(String.t() | nil, String.t(), pos_integer(), String.t() | nil) :: String.t() | nil
  def default_plan_id(nil, _profile_kind, _profile_version, _route_key), do: nil

  def default_plan_id(run_id, profile_kind, profile_version, route_key)
      when is_binary(run_id) and is_binary(profile_kind) and is_integer(profile_version) do
    route = route_key || @default_route_segment
    "#{@default_plan_id_prefix}:#{run_id}:#{profile_kind}:v#{profile_version}:#{route}"
  end
end
