defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Routes do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.Options
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @default_policy_by_route_key %{
    :planning => %{action: :transition_then_dispatch, transition_target: :developing},
    :developing => %{action: :dispatch},
    Contract.review_route_key() => %{action: :wait},
    :merging => %{action: :dispatch, execution_profile: Contract.land_execution_profile()},
    Contract.rework_route_key() => %{action: :dispatch},
    :resolved => %{action: :stop},
    :rejected => %{action: :stop}
  }

  @lifecycle_phase_by_route_key %{
    :planning => WorkflowLifecycle.todo(),
    :developing => WorkflowLifecycle.in_progress(),
    Contract.review_route_key() => WorkflowLifecycle.human_review(),
    :merging => WorkflowLifecycle.merging(),
    Contract.rework_route_key() => WorkflowLifecycle.rework(),
    :resolved => WorkflowLifecycle.done(),
    :rejected => WorkflowLifecycle.canceled()
  }

  @spec route_keys() :: [atom()]
  def route_keys, do: Contract.route_keys()

  @spec default_policy_by_route_key() :: map()
  def default_policy_by_route_key, do: @default_policy_by_route_key

  @spec default_policy_by_route_key(term()) :: map()
  def default_policy_by_route_key(options) do
    Enum.reduce(Contract.configurable_route_keys(), @default_policy_by_route_key, fn route_key, policy_by_route_key ->
      maybe_disable_route(policy_by_route_key, route_key, Options.route_enabled?(options, route_key))
    end)
  end

  @spec lifecycle_phase_by_route_key() :: map()
  def lifecycle_phase_by_route_key, do: @lifecycle_phase_by_route_key

  @spec enabled_completion_route_keys(term()) :: [atom()]
  def enabled_completion_route_keys(options) do
    Enum.filter(Contract.default_completion_route_keys(), &Options.route_enabled?(options, &1))
  end

  defp maybe_disable_route(policy_by_route_key, _route_key, true), do: policy_by_route_key

  defp maybe_disable_route(policy_by_route_key, route_key, false) when is_atom(route_key) do
    Map.put(policy_by_route_key, route_key, %{action: :disabled})
  end
end
