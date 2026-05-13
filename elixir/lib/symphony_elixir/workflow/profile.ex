defmodule SymphonyElixir.Workflow.Profile do
  @moduledoc """
  Behaviour for workflow-profile modules.

  A profile owns business route vocabulary and defaults. Trackers own raw state
  transport, and route policy owns the shared action semantics.
  """

  @type route_key :: atom()
  @type raw_state_by_route_key :: %{route_key() => String.t()}
  @type policy_by_route_key :: %{route_key() => map()}
  @type lifecycle_phase_by_route_key :: %{route_key() => String.t()}
  @type completion_contract :: %{
          required(:required_outputs) => [String.t()],
          required(:allowed_completion_routes) => [String.t()],
          required(:evidence_requirements) => [String.t()],
          required(:handoff_expectations) => [String.t()]
        }
  @type options :: map()

  @callback kind() :: String.t()
  @callback version() :: pos_integer()
  @callback route_keys() :: [route_key()]
  @callback default_raw_state_by_route_key() :: raw_state_by_route_key()
  @callback default_policy_by_route_key() :: policy_by_route_key()
  @callback lifecycle_phase_by_route_key() :: lifecycle_phase_by_route_key()
  @callback completion_contract(options()) :: completion_contract()
  @callback allowed_execution_profiles() :: [String.t()]
  @callback default_options() :: options()
  @callback validate_options(options()) :: :ok | {:error, term()}
  @callback default_policy_by_route_key(options()) :: policy_by_route_key()
  @callback allowed_execution_profiles(options()) :: [String.t()]
  @callback runtime_execution_profile_extensions_enabled?(options()) :: boolean()
  @callback execution_profile_required_capabilities(String.t(), options()) :: [String.t()]
  @callback required_capabilities(options()) :: [String.t()]
  @callback optional_capabilities(options()) :: [String.t()]
end
