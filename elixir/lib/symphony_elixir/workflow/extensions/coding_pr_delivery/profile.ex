defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile do
  @moduledoc """
  Built-in coding and PR delivery workflow profile.
  """

  @behaviour SymphonyElixir.Workflow.Profile

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Profile.{
    Capabilities,
    CompletionContract,
    Contract,
    Options,
    Routes
  }

  @impl true
  def kind, do: Contract.kind()

  @spec review_route_key() :: atom()
  def review_route_key, do: Contract.review_route_key()

  @impl true
  def version, do: Contract.version()

  @impl true
  def route_keys, do: Routes.route_keys()

  @impl true
  def default_policy_by_route_key, do: Routes.default_policy_by_route_key()

  @impl true
  def default_policy_by_route_key(options), do: Routes.default_policy_by_route_key(options)

  @impl true
  def lifecycle_phase_by_route_key, do: Routes.lifecycle_phase_by_route_key()

  @impl true
  def completion_contract(options), do: CompletionContract.build(options)

  @impl true
  def allowed_execution_profiles, do: Options.default_allowed_execution_profiles()

  @impl true
  def allowed_execution_profiles(options), do: Options.allowed_execution_profile_names(options)

  @impl true
  def runtime_execution_profile_extensions_enabled?(_options), do: true

  @impl true
  def execution_profile_required_capabilities(execution_profile, options),
    do: Capabilities.execution_profile_required_capabilities(execution_profile, options)

  @impl true
  def options_schema, do: Options.schema()

  @impl true
  def default_options, do: Options.default()

  @impl true
  def validate_options(options), do: Options.validate(options)

  @spec change_proposal_required?(term()) :: boolean()
  def change_proposal_required?(options), do: Options.change_proposal_required?(options)

  @spec review_handoff_change_proposal_checks_mode(term()) :: String.t()
  def review_handoff_change_proposal_checks_mode(options),
    do: Options.review_handoff_change_proposal_checks_mode(options)

  @spec review_handoff_change_proposal_checks_not_required?(term()) :: boolean()
  def review_handoff_change_proposal_checks_not_required?(options),
    do: Options.review_handoff_change_proposal_checks_not_required?(options)

  @spec review_handoff_change_proposal_checks_required_when_available() :: String.t()
  def review_handoff_change_proposal_checks_required_when_available,
    do: Contract.change_proposal_checks_required_when_available()

  @spec review_handoff_change_proposal_checks_not_required() :: String.t()
  def review_handoff_change_proposal_checks_not_required,
    do: Contract.change_proposal_checks_not_required()

  @impl true
  def required_capabilities(options), do: Capabilities.required_capabilities(options)

  @impl true
  def optional_capabilities(options), do: Capabilities.optional_capabilities(options)
end
