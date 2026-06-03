defmodule SymphonyElixir.Workflow.ChangeProposalReconciliation.Config do
  @moduledoc false

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  @max_processed_issues_per_cycle_limit 100

  @supported_fields [
    "enabled",
    "candidates",
    "gates",
    "outcome_routes",
    "thresholds"
  ]

  @candidate_fields [
    "discovery",
    "source_routes",
    "max_processed_issues_per_cycle"
  ]

  @candidate_discovery_modes [
    "source_route_scan",
    "runtime_targeted"
  ]

  @gate_fields [
    "approval_required",
    "passing_checks_required",
    "mergeable_required"
  ]

  @outcome_route_fields [
    "ready",
    "changes_requested",
    "failed_checks",
    "already_merged"
  ]

  @threshold_fields [
    "failed_checks_confirmation_count"
  ]

  @outcome_route_requirements [
    {:ready, "outcome_routes.ready", "merging", [:dispatch]},
    {:changes_requested, "outcome_routes.changes_requested", "rework", [:dispatch]},
    {:failed_checks, "outcome_routes.failed_checks", "rework", [:dispatch]},
    {:already_merged, "outcome_routes.already_merged", "done", [:stop]}
  ]

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

  @spec from_settings(map(), ProfileRegistry.resolved_profile() | nil) ::
          {:ok, t()} | {:error, term()}
  def from_settings(settings, profile_context \\ nil) when is_map(settings) do
    with {:ok, profile_context} <- resolve_profile_context(settings, profile_context),
         {:ok, attrs} <- change_proposal_attrs(settings),
         :ok <- validate_supported_fields(attrs),
         {:ok, config} <- parse(attrs, profile_context),
         :ok <- validate_enabled_config(config, settings, profile_context) do
      {:ok, config}
    end
  end

  @spec validate_settings(map(), ProfileRegistry.resolved_profile()) ::
          :ok | {:error, {:invalid_workflow_config, String.t()}}
  def validate_settings(settings, profile_context) when is_map(settings) do
    case from_settings(settings, profile_context) do
      {:ok, _config} -> :ok
      {:error, reason} -> {:error, {:invalid_workflow_config, format_error(reason)}}
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

  defp resolve_profile_context(_settings, %{module: module} = profile_context) when is_atom(module) do
    {:ok, profile_context}
  end

  defp resolve_profile_context(settings, _profile_context) do
    settings
    |> map_value("workflow")
    |> map_value("profile")
    |> ProfileRegistry.resolve()
  end

  defp change_proposal_attrs(settings) do
    case settings |> map_value("workflow") |> map_value("reconciliation") |> map_value("change_proposal") do
      nil -> {:ok, %{}}
      attrs when is_map(attrs) -> {:ok, attrs}
      attrs -> {:error, {:invalid_change_proposal_reconciliation_config, attrs}}
    end
  end

  defp validate_supported_fields(attrs) when is_map(attrs) do
    with :ok <- validate_known_fields(attrs, @supported_fields),
         :ok <- validate_section_fields(attrs, "candidates", @candidate_fields),
         :ok <- validate_section_fields(attrs, "gates", @gate_fields),
         :ok <- validate_section_fields(attrs, "outcome_routes", @outcome_route_fields),
         :ok <- validate_section_fields(attrs, "thresholds", @threshold_fields) do
      :ok
    end
  end

  defp validate_section_fields(attrs, section, supported_fields)
       when is_map(attrs) and is_binary(section) do
    case map_value(attrs, section) do
      nil ->
        :ok

      section_attrs when is_map(section_attrs) ->
        validate_known_fields(section_attrs, supported_fields, section)

      value ->
        {:error, {:invalid_section, section, value}}
    end
  end

  defp validate_known_fields(attrs, supported_fields, path_prefix \\ nil) when is_map(attrs) do
    unsupported_field =
      attrs
      |> Map.keys()
      |> Enum.find(fn field ->
        normalize_field_name(field) not in supported_fields
      end)

    case unsupported_field do
      nil -> :ok
      field -> {:error, {:unsupported_field, field_path(path_prefix, field)}}
    end
  end

  defp parse(attrs, profile_context) when is_map(attrs) do
    candidates = section_attrs(attrs, "candidates")
    gates = section_attrs(attrs, "gates")
    outcome_routes_attrs = section_attrs(attrs, "outcome_routes")
    thresholds = section_attrs(attrs, "thresholds")

    with {:ok, enabled?} <- boolean_field(attrs, "enabled", false),
         {:ok, candidate_discovery} <-
           candidate_discovery_field(candidates, "discovery", "candidates.discovery"),
         {:ok, source_routes} <-
           route_list_field(candidates, "source_routes", profile_context, "candidates.source_routes"),
         {:ok, outcome_routes} <- outcome_routes_field(outcome_routes_attrs, profile_context),
         {:ok, require_approval?} <-
           boolean_field(gates, "approval_required", true, "gates.approval_required"),
         {:ok, require_passing_checks?} <-
           boolean_field(gates, "passing_checks_required", true, "gates.passing_checks_required"),
         {:ok, require_mergeable?} <-
           boolean_field(gates, "mergeable_required", true, "gates.mergeable_required"),
         {:ok, failed_checks_confirmation_count} <-
           positive_integer_field(
             thresholds,
             "failed_checks_confirmation_count",
             2,
             "thresholds.failed_checks_confirmation_count"
           ),
         {:ok, max_processed_candidate_issues_per_cycle} <-
           positive_integer_field(
             candidates,
             "max_processed_issues_per_cycle",
             25,
             "candidates.max_processed_issues_per_cycle"
           ),
         :ok <-
           validate_processed_issues_limit(max_processed_candidate_issues_per_cycle) do
      {:ok,
       %__MODULE__{
         enabled?: enabled?,
         candidate_discovery: candidate_discovery,
         source_routes: source_routes,
         outcome_routes: outcome_routes,
         require_approval?: require_approval?,
         require_passing_checks?: require_passing_checks?,
         require_mergeable?: require_mergeable?,
         failed_checks_confirmation_count: failed_checks_confirmation_count,
         max_processed_candidate_issues_per_cycle: max_processed_candidate_issues_per_cycle
       }}
    end
  end

  defp section_attrs(attrs, section) when is_map(attrs) and is_binary(section) do
    case map_value(attrs, section) do
      section_attrs when is_map(section_attrs) -> section_attrs
      _value -> %{}
    end
  end

  defp validate_enabled_config(%__MODULE__{enabled?: false}, _settings, _profile_context), do: :ok

  defp validate_enabled_config(%__MODULE__{} = config, settings, profile_context) do
    cond do
      config.source_routes == [] ->
        {:error, :missing_source_routes}

      is_nil(outcome_route(config, :ready)) ->
        {:error, :missing_ready_target_route}

      true ->
        with :ok <- validate_source_routes(config.source_routes, profile_context),
             :ok <- validate_target_routes(config, settings, profile_context) do
          :ok
        end
    end
  end

  defp validate_source_routes(source_routes, %{module: profile_module}) when is_list(source_routes) do
    Enum.reduce_while(source_routes, :ok, fn %RouteRef{} = source_route, :ok ->
      phase = RoutePolicy.expected_lifecycle_phase(source_route.route_key, profile_module)

      if WorkflowLifecycle.dispatch_blocker_phase?(phase) do
        {:halt, {:error, {:source_route_is_active_execution_phase, source_route, phase}}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp validate_target_routes(
         %__MODULE__{} = config,
         settings,
         %{module: profile_module} = profile_context
       ) do
    policy_by_route_key = effective_policy_by_route_key(settings, profile_context)

    Enum.reduce_while(@outcome_route_requirements, :ok, fn
      {outcome, field_path, expected_phase, expected_actions}, :ok ->
        config
        |> outcome_route(outcome)
        |> validate_target_route(
          field_path,
          expected_phase,
          expected_actions,
          policy_by_route_key,
          profile_module
        )
        |> case do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp validate_target_route(
         nil,
         _field_path,
         _expected_phase,
         _expected_actions,
         _policy_by_route_key,
         _profile_module
       ),
       do: :ok

  defp validate_target_route(
         %RouteRef{} = route_ref,
         field_path,
         expected_phase,
         expected_actions,
         policy_by_route_key,
         profile_module
       ) do
    route_key = route_ref.route_key
    phase = RoutePolicy.expected_lifecycle_phase(route_key, profile_module)
    action = route_policy_action(policy_by_route_key, route_key)

    cond do
      WorkflowLifecycle.normalize_phase(phase) != expected_phase ->
        {:error, {:invalid_target_route_lifecycle_phase, field_path, route_ref, phase, expected_phase}}

      action not in expected_actions ->
        {:error, {:invalid_target_route_policy_action, field_path, route_ref, action, expected_actions}}

      true ->
        :ok
    end
  end

  defp effective_policy_by_route_key(settings, %{module: profile_module, options: profile_options}) do
    default_policy_by_route_key = ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)

    settings
    |> map_value("tracker")
    |> tracker_lifecycle()
    |> map_value("policy_by_route_key")
    |> RoutePolicy.resolve_policy_by_route_key(default_policy_by_route_key, profile_module)
  end

  defp tracker_lifecycle(tracker) when is_map(tracker), do: map_value(tracker, "lifecycle") || %{}
  defp tracker_lifecycle(_tracker), do: %{}

  defp route_policy_action(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    policy_by_route_key
    |> effective_route_policy(route_key)
    |> Map.get(:action)
  end

  defp route_policy_action(_policy_by_route_key, _route_key), do: nil

  defp effective_route_policy(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    RoutePolicy.policy_for_route_key(policy_by_route_key, route_key)
  end

  defp outcome_routes_field(outcome_routes, profile_context) when is_map(outcome_routes) do
    with {:ok, ready_route} <- route_field(outcome_routes, "ready", profile_context, "outcome_routes.ready"),
         {:ok, changes_requested_route} <-
           route_field(
             outcome_routes,
             "changes_requested",
             profile_context,
             "outcome_routes.changes_requested"
           ),
         {:ok, failed_checks_route} <-
           route_field(outcome_routes, "failed_checks", profile_context, "outcome_routes.failed_checks"),
         {:ok, already_merged_route} <-
           route_field(outcome_routes, "already_merged", profile_context, "outcome_routes.already_merged") do
      {:ok,
       %{}
       |> maybe_put_outcome_route(:ready, ready_route)
       |> maybe_put_outcome_route(:changes_requested, changes_requested_route)
       |> maybe_put_outcome_route(:failed_checks, failed_checks_route)
       |> maybe_put_outcome_route(:already_merged, already_merged_route)}
    end
  end

  defp maybe_put_outcome_route(outcome_routes, _outcome, nil), do: outcome_routes
  defp maybe_put_outcome_route(outcome_routes, outcome, %RouteRef{} = route_ref), do: Map.put(outcome_routes, outcome, route_ref)

  defp route_list_field(attrs, key, profile_context, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        values
        |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
          case route_ref(value, profile_context) do
            {:ok, route_ref} -> {:cont, {:ok, acc ++ [route_ref]}}
            {:error, reason} -> {:halt, {:error, {:invalid_route_key, field_path, reason}}}
          end
        end)
        |> case do
          {:ok, routes} -> {:ok, Enum.uniq(routes)}
          {:error, _reason} = error -> error
        end

      value ->
        {:error, {:invalid_route_list, field_path, value}}
    end
  end

  defp candidate_discovery_field(attrs, key, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, :source_route_scan}

      value when is_binary(value) ->
        normalized =
          value
          |> String.trim()
          |> String.downcase()

        case normalized do
          "source_route_scan" ->
            {:ok, :source_route_scan}

          "runtime_targeted" ->
            {:ok, :runtime_targeted}

          _other ->
            {:error, {:invalid_candidate_discovery, field_path, value, @candidate_discovery_modes}}
        end

      value ->
        {:error, {:invalid_candidate_discovery, field_path, value, @candidate_discovery_modes}}
    end
  end

  defp route_field(attrs, key, profile_context, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, nil}

      value ->
        case route_ref(value, profile_context) do
          {:ok, route_ref} -> {:ok, route_ref}
          {:error, reason} -> {:error, {:invalid_route_key, field_path, reason}}
        end
    end
  end

  defp route_ref(value, profile_context), do: RouteRef.new(profile_context, value)

  defp boolean_field(attrs, key, default, field_path \\ nil) when is_map(attrs) and is_binary(key) do
    field_path = field_path || key

    case map_value(attrs, key) do
      nil -> {:ok, default}
      value when is_boolean(value) -> {:ok, value}
      value -> {:error, {:invalid_boolean, field_path, value}}
    end
  end

  defp positive_integer_field(attrs, key, default, field_path)
       when is_map(attrs) and is_binary(key) do
    case map_value(attrs, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value ->
        {:error, {:invalid_positive_integer, field_path, value}}
    end
  end

  defp validate_processed_issues_limit(value)
       when value <= @max_processed_issues_per_cycle_limit,
       do: :ok

  defp validate_processed_issues_limit(value) do
    {:error, {:max_processed_issues_per_cycle_too_large, "candidates.max_processed_issues_per_cycle", value, @max_processed_issues_per_cycle_limit}}
  end

  defp format_error(reason) do
    "workflow.reconciliation.change_proposal is invalid: #{inspect(reason)}"
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> map_get_existing_atom(map, key)
    end
  end

  defp map_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp normalize_field_name(field) when is_atom(field), do: Atom.to_string(field)
  defp normalize_field_name(field) when is_binary(field), do: field
  defp normalize_field_name(field), do: field

  defp field_path(nil, field), do: display_field_name(field)
  defp field_path(path_prefix, field), do: path_prefix <> "." <> display_field_name(field)

  defp display_field_name(field) when is_binary(field), do: field
  defp display_field_name(field) when is_atom(field), do: Atom.to_string(field)
  defp display_field_name(field), do: inspect(field)
end
