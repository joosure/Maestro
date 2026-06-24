defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Routes do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.RouteContextDefaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Source
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef

  @spec route_list_field(map(), String.t(), map(), String.t()) :: {:ok, [RouteRef.t()]} | {:error, term()}
  def route_list_field(attrs, key, profile_context, field_path)
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

  @spec outcome_routes_field(map(), map()) :: {:ok, %{optional(Config.outcome()) => RouteRef.t()}} | {:error, term()}
  def outcome_routes_field(outcome_routes, profile_context) when is_map(outcome_routes) do
    Contract.outcome_route_specs()
    |> Enum.reduce_while({:ok, %{}}, fn {outcome, field_key, field_path}, {:ok, acc} ->
      case route_field(outcome_routes, field_key, profile_context, field_path) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, %RouteRef{} = route_ref} -> {:cont, {:ok, Map.put(acc, outcome, route_ref)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec validate_source_routes([RouteRef.t()], Config.profile_context()) :: :ok | {:error, term()}
  def validate_source_routes(source_routes, %{module: profile_module}) when is_list(source_routes) do
    Enum.reduce_while(source_routes, :ok, fn %RouteRef{} = source_route, :ok ->
      phase = RoutePolicy.expected_lifecycle_phase(source_route.route_key, profile_module)

      if WorkflowLifecycle.dispatch_blocker_phase?(phase) do
        {:halt, {:error, {:source_route_is_active_execution_phase, source_route, phase}}}
      else
        {:cont, :ok}
      end
    end)
  end

  @spec validate_target_routes(Config.t(), map(), Config.profile_context()) :: :ok | {:error, term()}
  def validate_target_routes(
        %Config{} = config,
        settings,
        %{module: profile_module} = profile_context
      ) do
    policy_by_route_key = effective_policy_by_route_key(settings, profile_context)

    Enum.reduce_while(Contract.outcome_route_requirements(), :ok, fn
      {outcome, field_path, expected_phase, expected_actions}, :ok ->
        config
        |> Config.outcome_route(outcome)
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

  defp effective_policy_by_route_key(settings, %{module: profile_module} = profile_context) do
    profile_options = Map.get(profile_context, :options, %{})

    default_policy_by_route_key =
      RouteContextDefaults.default_policy_by_route_key(%{module: profile_module, options: profile_options})

    settings
    |> Source.policy_by_route_key()
    |> RoutePolicy.resolve_policy_by_route_key(default_policy_by_route_key, profile_module)
  end

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

  defp map_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil
end
