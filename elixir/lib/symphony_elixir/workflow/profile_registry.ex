defmodule SymphonyElixir.Workflow.ProfileRegistry do
  @moduledoc """
  Static workflow-profile registry.

  Repository workflow config may select one of the compiled profile kind/version
  pairs, but it cannot register profile modules at runtime.
  """

  alias SymphonyElixir.Workflow.Profiles.{
    CodingPrDelivery,
    RequirementAnalysis,
    RequirementRefinement,
    ReviewRouting,
    Triage
  }

  alias SymphonyElixir.Workflow.Profile.{Config, Defaults, Resolved}
  alias SymphonyElixir.Workflow.RoutePolicy.Keys

  @profiles %{
    {"coding_pr_delivery", 1} => CodingPrDelivery,
    {"requirement_analysis", 1} => RequirementAnalysis,
    {"requirement_refinement", 1} => RequirementRefinement,
    {"review_routing", 1} => ReviewRouting,
    {"triage", 1} => Triage
  }

  @default_versions %{
    "coding_pr_delivery" => 1,
    "requirement_analysis" => 1,
    "requirement_refinement" => 1,
    "review_routing" => 1,
    "triage" => 1
  }

  @default_profile_kind "coding_pr_delivery"
  @default_profile {@default_profile_kind, Map.fetch!(@default_versions, @default_profile_kind)}

  @type resolved_profile :: Resolved.t()

  @spec default_profile_module() :: module()
  def default_profile_module, do: CodingPrDelivery

  @spec default_version(String.t()) :: {:ok, pos_integer()} | {:error, term()}
  def default_version(kind) when is_binary(kind) do
    case Map.fetch(@default_versions, kind) do
      {:ok, version} -> {:ok, version}
      :error -> {:error, {:unsupported_workflow_profile_kind, kind}}
    end
  end

  def default_version(kind), do: {:error, {:invalid_workflow_profile_kind, kind}}

  @spec default_profile_config() :: map()
  def default_profile_config do
    {kind, version} = @default_profile

    %{
      kind: kind,
      version: version,
      options: default_profile_module().default_options()
    }
    |> Config.new!()
    |> Config.to_map()
  end

  @spec fetch(String.t(), pos_integer()) :: {:ok, module()} | {:error, term()}
  def fetch(kind, version) when is_binary(kind) and is_integer(version) and version > 0 do
    case Map.fetch(@profiles, {kind, version}) do
      {:ok, profile_module} -> {:ok, profile_module}
      :error -> {:error, {:unsupported_workflow_profile, kind, version}}
    end
  end

  def fetch(kind, version), do: {:error, {:invalid_workflow_profile, kind, version}}

  @spec fetch!(String.t(), pos_integer()) :: module()
  def fetch!(kind, version) do
    case fetch(kind, version) do
      {:ok, profile_module} -> profile_module
      {:error, reason} -> raise ArgumentError, "invalid workflow profile: #{inspect(reason)}"
    end
  end

  @spec profiles() :: [module()]
  def profiles, do: Map.values(@profiles)

  @spec normalize_config(map() | nil) :: map()
  def normalize_config(profile_config) when is_map(profile_config) do
    kind =
      profile_config
      |> map_value("kind")
      |> normalize_kind()
      |> case do
        nil -> elem(@default_profile, 0)
        normalized_kind -> normalized_kind
      end

    raw_version = map_value(profile_config, "version")

    version =
      case raw_version do
        nil -> default_version_for_kind(kind)
        value -> normalize_version(value) || value
      end

    module = Map.get(@profiles, {kind, version})

    default_options =
      case module do
        module when is_atom(module) and not is_nil(module) -> module.default_options()
        _ -> %{}
      end

    options =
      default_options
      |> deep_merge(normalize_options(map_value(profile_config, "options")))

    %{"kind" => kind, "version" => version, "options" => options}
  end

  def normalize_config(_profile_config), do: default_profile_config()

  @spec resolve_config(map() | nil) :: {:ok, Config.t()} | {:error, term()}
  def resolve_config(nil), do: {:ok, Config.new!(default_profile_config())}

  def resolve_config(profile_config) when is_map(profile_config) do
    with :ok <- validate_profile_config_shape(profile_config) do
      {:ok, profile_config |> normalize_config() |> Config.new!()}
    end
  end

  def resolve_config(profile_config), do: {:error, {:invalid_workflow_profile_config, profile_config}}

  @spec resolve(map() | nil) :: {:ok, resolved_profile()} | {:error, term()}
  def resolve(profile_config) do
    with {:ok, normalized_config} <- resolve_config(profile_config),
         {:ok, profile_module} <- fetch(normalized_config.kind, normalized_config.version),
         :ok <- profile_module.validate_options(normalized_config.options),
         :ok <- validate_completion_contract(profile_module, normalized_config.options) do
      {:ok, Resolved.from_config(normalized_config, profile_module)}
    end
  end

  @spec resolve!(map() | nil) :: resolved_profile()
  def resolve!(profile_config) do
    case resolve(profile_config) do
      {:ok, resolved_profile} -> resolved_profile
      {:error, reason} -> raise ArgumentError, "invalid workflow profile: #{inspect(reason)}"
    end
  end

  @spec defaults(module(), map()) :: Defaults.t()
  def defaults(profile_module, options \\ %{}) when is_atom(profile_module) do
    Defaults.new!(%{
      route_keys: profile_module.route_keys(),
      raw_state_by_route_key: profile_module.default_raw_state_by_route_key(),
      policy_by_route_key: profile_module.default_policy_by_route_key(options),
      lifecycle_phase_by_route_key: profile_module.lifecycle_phase_by_route_key(),
      completion_contract: profile_module.completion_contract(options),
      allowed_execution_profiles: profile_module.allowed_execution_profiles(options),
      required_capabilities: profile_module.required_capabilities(options),
      optional_capabilities: profile_module.optional_capabilities(options)
    })
  end

  @spec default_policy_by_route_key(module(), map()) :: map()
  def default_policy_by_route_key(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module
    |> defaults(options)
    |> Map.fetch!(:policy_by_route_key)
  end

  @spec allowed_execution_profiles(module(), map()) :: [String.t()]
  def allowed_execution_profiles(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module
    |> defaults(options)
    |> Map.fetch!(:allowed_execution_profiles)
  end

  @spec runtime_execution_profile_extensions_enabled?(module(), map()) :: boolean()
  def runtime_execution_profile_extensions_enabled?(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module.runtime_execution_profile_extensions_enabled?(options)
  end

  @spec required_capabilities(module(), map()) :: [String.t()]
  def required_capabilities(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module
    |> defaults(options)
    |> Map.fetch!(:required_capabilities)
  end

  @spec execution_profile_required_capabilities(module(), String.t(), map()) :: [String.t()]
  def execution_profile_required_capabilities(profile_module, execution_profile, options \\ %{})
      when is_atom(profile_module) and is_binary(execution_profile) do
    profile_module.execution_profile_required_capabilities(execution_profile, options)
  end

  @spec optional_capabilities(module(), map()) :: [String.t()]
  def optional_capabilities(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module
    |> defaults(options)
    |> Map.fetch!(:optional_capabilities)
  end

  @spec completion_contract(module(), map()) :: map()
  def completion_contract(profile_module, options \\ %{}) when is_atom(profile_module) do
    profile_module
    |> defaults(options)
    |> Map.fetch!(:completion_contract)
  end

  @spec validate_completion_contract(module(), map()) :: :ok | {:error, term()}
  def validate_completion_contract(profile_module, options \\ %{}) when is_atom(profile_module) do
    contract = completion_contract(profile_module, options)

    with :ok <- validate_completion_contract_shape(profile_module, contract),
         :ok <- validate_completion_contract_routes(profile_module, contract) do
      :ok
    end
  end

  defp default_version_for_kind(kind) when is_binary(kind) do
    case default_version(kind) do
      {:ok, version} -> version
      {:error, _reason} -> elem(@default_profile, 1)
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    if Map.has_key?(map, key) do
      Map.fetch!(map, key)
    else
      map_get_existing_atom(map, key)
    end
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_kind(nil), do: nil

  defp normalize_kind(kind) when is_atom(kind) do
    kind
    |> Atom.to_string()
    |> normalize_kind()
  end

  defp normalize_kind(_kind), do: nil

  defp normalize_version(version) when is_integer(version) and version > 0, do: version

  defp normalize_version(version) when is_binary(version) do
    case Integer.parse(String.trim(version)) do
      {parsed_version, ""} when parsed_version > 0 -> parsed_version
      _ -> nil
    end
  end

  defp normalize_version(_version), do: nil

  defp normalize_options(options) when is_map(options) do
    Map.new(options, fn {key, value} -> {to_string(key), normalize_option_value(value)} end)
  end

  defp normalize_options(_options), do: %{}

  defp normalize_option_value(value) when is_map(value), do: normalize_options(value)
  defp normalize_option_value(values) when is_list(values), do: Enum.map(values, &normalize_option_value/1)
  defp normalize_option_value(value), do: value

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp validate_profile_config_shape(profile_config) when is_map(profile_config) do
    with :ok <- validate_profile_kind_field(profile_config),
         :ok <- validate_profile_options_field(profile_config) do
      :ok
    end
  end

  defp validate_profile_kind_field(profile_config) when is_map(profile_config) do
    if map_has_key?(profile_config, "kind") do
      case map_value(profile_config, "kind") do
        nil -> :ok
        kind when is_binary(kind) -> :ok
        kind when is_atom(kind) and not is_boolean(kind) -> :ok
        kind -> {:error, {:invalid_workflow_profile_kind, kind}}
      end
    else
      :ok
    end
  end

  defp validate_profile_options_field(profile_config) when is_map(profile_config) do
    if map_has_key?(profile_config, "options") do
      case map_value(profile_config, "options") do
        nil -> :ok
        options when is_map(options) -> :ok
        options -> {:error, {:invalid_workflow_profile_options, options}}
      end
    else
      :ok
    end
  end

  defp map_has_key?(map, key) when is_map(map) and is_binary(key) do
    Map.has_key?(map, key) or map_has_existing_atom_key?(map, key)
  end

  defp map_has_existing_atom_key?(map, key) when is_map(map) and is_binary(key) do
    Map.has_key?(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> false
  end

  defp validate_completion_contract_shape(profile_module, contract) when is_map(contract) do
    required_keys = [
      :required_outputs,
      :allowed_completion_routes,
      :evidence_requirements,
      :handoff_expectations
    ]

    Enum.reduce_while(required_keys, :ok, fn key, :ok ->
      case Map.get(contract, key) || Map.get(contract, Atom.to_string(key)) do
        values when is_list(values) ->
          if Enum.all?(values, &(is_binary(&1) and String.trim(&1) != "")) do
            {:cont, :ok}
          else
            {:halt, {:error, {:invalid_completion_contract_field, profile_module.kind(), key, values}}}
          end

        values ->
          {:halt, {:error, {:invalid_completion_contract_field, profile_module.kind(), key, values}}}
      end
    end)
  end

  defp validate_completion_contract_routes(profile_module, contract) do
    contract
    |> map_value("allowed_completion_routes")
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn route_key, :ok ->
      if Keys.route_key?(route_key, profile_module) do
        {:cont, :ok}
      else
        {:halt, {:error, {:invalid_completion_contract_route, profile_module.kind(), route_key}}}
      end
    end)
  end
end
