defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.ReviewHandoff.Target do
  @moduledoc """
  Target and profile projection helpers for Coding PR Delivery review handoff.
  """

  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile, as: CodingPrDelivery
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.RoutePolicy

  @review_target_names ["review", "in_review", "human_review"]
  @target_name_separator_pattern ~r/[\s-]+/
  @target_name_separator "_"
  @profile_kind_key "profile_kind"
  @profile_version_key "profile_version"
  @profile_key "profile"
  @kind_key "kind"
  @version_key "version"
  @profile_options_key "profile_options"
  @profile_options_camel_key "profileOptions"
  @raw_state_by_route_key_key "raw_state_by_route_key"
  @raw_state_by_route_key_camel_key "rawStateByRouteKey"
  @state_phase_map_key "state_phase_map"
  @state_phase_map_camel_key "statePhaseMap"

  @spec review_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  def review_target?(workflow, target_state_name) do
    profile_kind(workflow) == CodingPrDelivery.kind() and
      (route_key_for_state(workflow, target_state_name) == CodingPrDelivery.review_route_key() or
         WorkflowLifecycle.human_review_phase?(lifecycle_phase_for_state(workflow, target_state_name)) or
         logical_review_target?(target_state_name))
  end

  @spec workflow_profile_ref(Effective.t() | map() | nil) :: map()
  def workflow_profile_ref(workflow) do
    %{
      kind: profile_kind(workflow),
      version: profile_version(workflow)
    }
  end

  @spec change_proposal_required?(Effective.t() | map() | nil) :: boolean()
  def change_proposal_required?(workflow) do
    workflow
    |> profile_options()
    |> CodingPrDelivery.change_proposal_required?()
  end

  @spec change_proposal_checks_not_required?(Effective.t() | map() | nil) :: boolean()
  def change_proposal_checks_not_required?(workflow) do
    workflow
    |> profile_options()
    |> CodingPrDelivery.review_handoff_change_proposal_checks_not_required?()
  end

  defp route_key_for_state(workflow, state_name) when is_binary(state_name) do
    RoutePolicy.route_key_for_raw_state(state_name, raw_state_by_route_key(workflow), CodingPrDelivery)
  end

  defp route_key_for_state(_workflow, _state_name), do: nil

  defp lifecycle_phase_for_state(workflow, state_name) when is_binary(state_name) do
    WorkflowLifecycle.phase_for_state(state_name, state_phase_map(workflow))
  end

  defp lifecycle_phase_for_state(_workflow, _state_name), do: nil

  defp logical_review_target?(target_state_name) when is_binary(target_state_name) do
    RoutePolicy.normalize_route_key(target_state_name, CodingPrDelivery) == CodingPrDelivery.review_route_key() or
      WorkflowLifecycle.human_review_phase?(target_state_name) or
      normalized_target_name(target_state_name) in @review_target_names
  end

  defp logical_review_target?(_target_state_name), do: false

  defp normalized_target_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(@target_name_separator_pattern, @target_name_separator)
  end

  defp profile_kind(%Effective{profile_kind: profile_kind}), do: profile_kind
  defp profile_kind(%{profile_kind: profile_kind}) when is_binary(profile_kind), do: profile_kind
  defp profile_kind(%{@profile_kind_key => profile_kind}) when is_binary(profile_kind), do: profile_kind
  defp profile_kind(%{profile: %{kind: kind}}) when is_binary(kind), do: kind
  defp profile_kind(%{@profile_key => %{@kind_key => kind}}) when is_binary(kind), do: kind
  defp profile_kind(_workflow), do: nil

  defp profile_version(%Effective{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{@profile_version_key => version}) when is_integer(version), do: version
  defp profile_version(%{profile: %{version: version}}) when is_integer(version), do: version
  defp profile_version(%{@profile_key => %{@version_key => version}}) when is_integer(version), do: version
  defp profile_version(workflow), do: if(profile_kind(workflow) == CodingPrDelivery.kind(), do: CodingPrDelivery.version())

  defp profile_options(%Effective{profile_options: options}) when is_map(options), do: options
  defp profile_options(%{profile_options: options}) when is_map(options), do: options
  defp profile_options(%{@profile_options_key => options}) when is_map(options), do: options
  defp profile_options(%{@profile_options_camel_key => options}) when is_map(options), do: options
  defp profile_options(_workflow), do: %{}

  defp raw_state_by_route_key(%Effective{raw_state_by_route_key: map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{raw_state_by_route_key: map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{@raw_state_by_route_key_key => map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{@raw_state_by_route_key_camel_key => map}) when is_map(map), do: map
  defp raw_state_by_route_key(_workflow), do: %{}

  defp state_phase_map(%Effective{state_phase_map: map}) when is_map(map), do: map
  defp state_phase_map(%{state_phase_map: map}) when is_map(map), do: map
  defp state_phase_map(%{@state_phase_map_key => map}) when is_map(map), do: map
  defp state_phase_map(%{@state_phase_map_camel_key => map}) when is_map(map), do: map
  defp state_phase_map(_workflow), do: %{}
end
