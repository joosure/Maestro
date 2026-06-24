defmodule SymphonyElixir.Workflow.StateTransitionReadiness do
  @moduledoc """
  Generic facade for backend-owned workflow state-transition readiness.

  Profile-owned policies are registered through the state-transition readiness
  policy registry instead of being hardcoded inside tracker adapters.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry

  @typed_tool_not_ready_error_code "transition_readiness_not_ready"

  @type policy_resolution ::
          {:ok, module()}
          | {:ok, :not_governed}
          | {:error, {:ambiguous_readiness_policy, [String.t()]}}

  @spec typed_tool_not_ready_error_code() :: String.t()
  def typed_tool_not_ready_error_code, do: @typed_tool_not_ready_error_code

  @spec resolve_policy(map() | struct() | nil, String.t() | nil, keyword()) :: policy_resolution()
  def resolve_policy(workflow, target_state_name, opts \\ []) when is_list(opts) do
    matching_policies =
      opts
      |> readiness_policies()
      |> Enum.filter(fn policy -> policy.governed_target?(workflow, target_state_name) end)

    case matching_policies do
      [] -> {:ok, :not_governed}
      [policy] -> {:ok, policy}
      policies -> {:error, {:ambiguous_readiness_policy, Enum.map(policies, &policy_id/1)}}
    end
  end

  @spec governed_target?(map() | struct() | nil, String.t() | nil) :: boolean()
  def governed_target?(workflow, target_state_name),
    do: governed_target?(workflow, target_state_name, [])

  @spec governed_target?(map() | struct() | nil, String.t() | nil, keyword()) :: boolean()
  def governed_target?(workflow, target_state_name, opts) when is_list(opts) do
    case resolve_policy(workflow, target_state_name, opts) do
      {:ok, :not_governed} -> false
      {:ok, policy} when is_atom(policy) -> true
      {:error, {:ambiguous_readiness_policy, _policy_ids}} -> true
    end
  end

  @spec validate(map() | struct() | nil, map(), keyword()) :: :ok | {:error, term()}
  def validate(workflow, issue, opts \\ []) do
    target_state_name = Keyword.get(opts, :target_state_name)

    case resolve_policy(workflow, target_state_name, opts) do
      {:ok, :not_governed} -> :ok
      {:ok, policy} -> policy.validate(workflow, issue, opts)
      {:error, _reason} = error -> error
    end
  end

  defp readiness_policies(opts),
    do: Keyword.get(opts, :readiness_policies, PolicyRegistry.policies())

  defp policy_id(policy) do
    if function_exported?(policy, :policy_id, 0) do
      policy.policy_id()
    else
      inspect(policy)
    end
  end
end
