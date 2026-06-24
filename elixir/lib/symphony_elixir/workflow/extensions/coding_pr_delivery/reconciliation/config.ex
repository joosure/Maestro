defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Error
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Parser
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Source
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Validator
  alias SymphonyElixir.Workflow.RouteRef

  defstruct enabled?: false,
            candidate_discovery: :source_route_scan,
            source_routes: [],
            outcome_routes: %{},
            require_approval?: true,
            require_passing_checks?: true,
            require_mergeable?: true,
            failed_checks_confirmation_count: 2,
            max_processed_candidate_issues_per_cycle: 25

  @type outcome :: :ready | :changes_requested | :failed_checks | :already_merged
  @type profile_context :: %{required(:module) => module(), optional(:options) => map(), optional(atom()) => term()}

  @type t :: %__MODULE__{
          enabled?: boolean(),
          candidate_discovery: :source_route_scan | :runtime_targeted,
          source_routes: [RouteRef.t()],
          outcome_routes: %{optional(outcome()) => RouteRef.t()},
          require_approval?: boolean(),
          require_passing_checks?: boolean(),
          require_mergeable?: boolean(),
          failed_checks_confirmation_count: pos_integer(),
          max_processed_candidate_issues_per_cycle: pos_integer()
        }

  @spec from_settings(map(), profile_context() | nil) :: {:ok, t()} | {:error, term()}
  def from_settings(settings, profile_context \\ nil) when is_map(settings) do
    with {:ok, profile_context} <- Source.resolve_profile_context(settings, profile_context),
         {:ok, attrs} <- Source.extension_attrs(settings),
         :ok <- Validator.validate_supported_fields(attrs),
         {:ok, config} <- Parser.parse(attrs, profile_context),
         :ok <- Validator.validate_enabled_config(config, settings, profile_context) do
      {:ok, config}
    end
  end

  @spec config_path() :: [String.t()]
  def config_path, do: Contract.config_path()

  @spec config_path_name() :: String.t()
  def config_path_name, do: Contract.config_path_name()

  @spec validate_settings(map(), profile_context()) :: :ok | {:error, {:invalid_workflow_config, String.t()}}
  def validate_settings(settings, profile_context) when is_map(settings) do
    case from_settings(settings, profile_context) do
      {:ok, _config} -> :ok
      {:error, reason} -> {:error, {:invalid_workflow_config, Error.format(reason)}}
    end
  end

  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{enabled?: enabled?}), do: enabled? == true

  @spec source_route_keys(t()) :: [atom()]
  def source_route_keys(%__MODULE__{source_routes: source_routes}) do
    Enum.map(source_routes, & &1.route_key)
  end

  @spec source_route?(t(), term()) :: boolean()
  def source_route?(%__MODULE__{} = config, route_key) when is_atom(route_key) do
    route_key in source_route_keys(config)
  end

  def source_route?(_config, _route_key), do: false

  @spec outcome_route(t(), outcome()) :: RouteRef.t() | nil
  def outcome_route(%__MODULE__{outcome_routes: outcome_routes}, outcome) when is_atom(outcome) do
    Map.get(outcome_routes, outcome)
  end
end
