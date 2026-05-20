defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policy do
  @moduledoc """
  Behaviour for workflow state-transition readiness policies.
  """

  @type validation_result :: :ok | {:error, term()}

  @callback policy_id() :: String.t()
  @callback schema() :: String.t()
  @callback governed_target?(map() | struct() | nil, String.t() | nil) :: boolean()
  @callback validate(map() | struct() | nil, map(), keyword()) :: validation_result()
end
