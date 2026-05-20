defmodule SymphonyElixir.Workflow.StateTransitionReadiness do
  @moduledoc """
  Generic facade for backend-owned workflow state-transition readiness.

  Profile-owned policies are registered through the state-transition readiness
  policy registry instead of being hardcoded inside tracker adapters.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.PolicyRegistry

  @spec governed_target?(map() | struct() | nil, String.t() | nil) :: boolean()
  def governed_target?(workflow, target_state_name) do
    Enum.any?(PolicyRegistry.policies(), fn policy ->
      policy.governed_target?(workflow, target_state_name)
    end)
  end

  @spec validate(map() | struct() | nil, map(), keyword()) :: :ok | {:error, term()}
  def validate(workflow, issue, opts \\ []) do
    Enum.reduce_while(PolicyRegistry.policies(), :ok, fn policy, :ok ->
      case policy.validate(workflow, issue, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end
end
