defmodule SymphonyElixir.Workflow.Readiness do
  @moduledoc """
  Builds structured workflow facts for route readiness, gates, and prompt
  rendering.

  This module is deliberately pure: it summarizes the resolved workflow
  contract and any caller-supplied evidence, but it does not perform tracker,
  repository, or provider side effects.
  """

  alias SymphonyElixir.Workflow.CompletionValidator
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RoutePolicy.Policy

  @empty_route %{
    "key" => nil,
    "raw_state" => nil,
    "lifecycle_phase" => nil,
    "action" => nil,
    "transition_target" => nil,
    "execution_profile" => nil,
    "policy" => %{}
  }

  @empty_contract %{
    "required_outputs" => [],
    "allowed_completion_routes" => [],
    "evidence_requirements" => [],
    "handoff_expectations" => []
  }

  @spec facts(map(), keyword() | map()) :: map()
  def facts(issue, opts \\ [])

  def facts(issue, opts) when is_map(issue) do
    profile_context = profile_context(issue, opts)
    route_facts = route_facts(issue, profile_context, opts)
    capabilities = capabilities(profile_context, route_facts, opts)
    evidence = completion_evidence(issue, opts)

    %{
      "profile" => profile_map(profile_context),
      "route" => route_map(route_facts),
      "completion_contract" => completion_contract(issue, profile_context),
      "capabilities" => capabilities,
      "gate" => gate(route_facts, capabilities, evidence)
    }
  end

  def facts(_issue, opts) do
    profile_context = profile_context(%{}, opts)
    capabilities = capabilities(profile_context, nil, opts)

    %{
      "profile" => profile_map(profile_context),
      "route" => @empty_route,
      "completion_contract" => completion_contract(%{}, profile_context),
      "capabilities" => capabilities,
      "gate" => no_route_gate()
    }
  end

  @spec gate(RouteFacts.t() | nil, map()) :: map()
  def gate(route_facts, capabilities), do: gate(route_facts, capabilities, %{})

  defp gate(route_facts, capabilities, evidence)

  defp gate(_route_facts, %{"missing" => missing}, _evidence) when is_list(missing) and missing != [] do
    %{
      "status" => "blocked",
      "gate" => "capability",
      "category" => "system",
      "reason" => "Required workflow capabilities are unavailable.",
      "required_evidence" => missing,
      "observed_evidence" => []
    }
  end

  defp gate(nil, _capabilities, _evidence), do: no_route_gate()

  defp gate(%RouteFacts{action: :wait, route_key: route_key, lifecycle_phase: lifecycle_phase} = route_facts, _capabilities, _evidence) do
    approval_gate? = route_key == :review
    human_review_gate? = WorkflowLifecycle.normalize_phase(lifecycle_phase) == "human_review"

    cond do
      approval_gate? ->
        %{
          "status" => "waiting",
          "gate" => "approval",
          "category" => "human",
          "reason" => "Waiting for human approval or review feedback.",
          "required_evidence" => [
            "human approval or requested-changes decision",
            "tracker or change-proposal review evidence"
          ],
          "observed_evidence" => observed_route_evidence(route_facts)
        }

      human_review_gate? ->
        %{
          "status" => "waiting",
          "gate" => "human_review",
          "category" => "human",
          "reason" => "Waiting for a human review decision.",
          "required_evidence" => ["human review decision"],
          "observed_evidence" => observed_route_evidence(route_facts)
        }

      true ->
        %{
          "status" => "waiting",
          "gate" => "route_wait",
          "category" => "workflow",
          "reason" => "Route policy is wait; automatic dispatch is not allowed.",
          "required_evidence" => ["route moves to a dispatchable state"],
          "observed_evidence" => observed_route_evidence(route_facts)
        }
    end
  end

  defp gate(%RouteFacts{action: :stop} = route_facts, _capabilities, _evidence) do
    %{
      "status" => "blocked",
      "gate" => "terminal",
      "category" => "workflow",
      "reason" => "Route policy is stop; no automatic dispatch is allowed.",
      "required_evidence" => ["new non-terminal route before more work can run"],
      "observed_evidence" => observed_route_evidence(route_facts)
    }
  end

  defp gate(%RouteFacts{action: :dispatch, route_key: :merging} = route_facts, capabilities, evidence) do
    merge_gate(route_facts, capabilities, evidence)
  end

  defp gate(%RouteFacts{action: :dispatch, execution_profile: execution_profile} = route_facts, capabilities, evidence)
       when is_binary(execution_profile) do
    if execution_profile == "land" do
      merge_gate(route_facts, capabilities, evidence)
    else
      dispatch_gate(route_facts)
    end
  end

  defp gate(%RouteFacts{action: :dispatch} = route_facts, _capabilities, _evidence) do
    dispatch_gate(route_facts)
  end

  defp gate(%RouteFacts{action: action} = route_facts, _capabilities, _evidence)
       when action in [:transition, :transition_then_dispatch] do
    %{
      "status" => "open",
      "gate" => "route_preparation",
      "category" => "workflow",
      "reason" => "Backend route preparation must complete before normal dispatch.",
      "required_evidence" => ["tracker state moved to the transition target route"],
      "observed_evidence" => observed_route_evidence(route_facts)
    }
  end

  defp gate(%RouteFacts{} = route_facts, _capabilities, _evidence) do
    %{
      "status" => "blocked",
      "gate" => "unknown_route_action",
      "category" => "workflow",
      "reason" => "Route policy action is not recognized by readiness facts.",
      "required_evidence" => ["valid route policy action"],
      "observed_evidence" => observed_route_evidence(route_facts)
    }
  end

  defp profile_context(issue, opts) when is_map(issue) do
    issue_profile =
      issue
      |> workflow_value(:profile)
      |> normalize_map()

    settings_profile =
      opts
      |> opt(:settings)
      |> map_field(:workflow)
      |> map_field(:profile)
      |> normalize_map()

    profile_config =
      cond do
        map_size(issue_profile) > 0 -> issue_profile
        map_size(settings_profile) > 0 -> settings_profile
        true -> ProfileRegistry.default_profile_config()
      end

    case ProfileRegistry.resolve(profile_config) do
      {:ok, resolved_profile} -> resolved_profile
      {:error, _reason} -> ProfileRegistry.resolve!(nil)
    end
  end

  defp route_facts(issue, profile_context, opts) do
    workflow = effective_workflow(issue, profile_context, opts)

    RouteFacts.from_fields(%{
      state: map_field(issue, :state),
      lifecycle_phase: map_field(issue, :lifecycle_phase),
      state_phase_map: Map.get(workflow, :state_phase_map, %{}),
      raw_state_by_route_key: Map.get(workflow, :raw_state_by_route_key, %{}),
      policy_by_route_key: Map.get(workflow, :policy_by_route_key, %{}),
      profile_module: profile_context.module
    }) || route_facts_from_lifecycle(issue, profile_context, workflow)
  end

  defp route_facts_from_lifecycle(issue, profile_context, workflow) do
    profile_module = profile_context.module
    state = map_field(issue, :state)

    lifecycle_phase =
      map_field(issue, :lifecycle_phase) ||
        WorkflowLifecycle.phase_for_state(state, Map.get(workflow, :state_phase_map, %{}))

    normalized_phase = WorkflowLifecycle.normalize_phase(lifecycle_phase)

    route_key =
      Enum.find(profile_module.route_keys(), fn route_key ->
        profile_module.lifecycle_phase_by_route_key()
        |> Map.get(route_key)
        |> WorkflowLifecycle.normalize_phase() == normalized_phase
      end)

    if is_atom(route_key) and not is_nil(normalized_phase) do
      policy =
        workflow
        |> Map.get(:policy_by_route_key, %{})
        |> policy_for_route_key(route_key)
        |> Policy.new!()

      RouteFacts.new!(%{
        route_key: route_key,
        raw_state: state || raw_state_for_route_key(workflow, route_key),
        lifecycle_phase: lifecycle_phase,
        policy: policy,
        action: policy.action,
        transition_target: policy.transition_target,
        execution_profile: policy.execution_profile
      })
    end
  end

  defp effective_workflow(issue, profile_context, opts) do
    profile_module = profile_context.module
    profile_options = profile_context.options
    settings_lifecycle = opts |> opt(:settings) |> map_field(:tracker) |> map_field(:lifecycle) |> normalize_map()
    type_workflow = workflow_for_type(settings_lifecycle, map_field(issue, :workitem_type_id))
    issue_workflow = map_field(issue, :workflow) |> normalize_map()

    raw_state_by_route_key =
      profile_module.default_raw_state_by_route_key()
      |> merge_raw_state_by_route_key(map_field(settings_lifecycle, :raw_state_by_route_key), profile_module)
      |> merge_raw_state_by_route_key(map_field(type_workflow, :raw_state_by_route_key), profile_module)
      |> merge_raw_state_by_route_key(map_field(issue_workflow, :raw_state_by_route_key), profile_module)

    policy_by_route_key =
      ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)
      |> resolve_policy_by_route_key(map_field(settings_lifecycle, :policy_by_route_key), profile_module)
      |> resolve_policy_by_route_key(map_field(type_workflow, :policy_by_route_key), profile_module)
      |> resolve_policy_by_route_key(map_field(issue_workflow, :policy_by_route_key), profile_module)

    state_phase_map =
      %{}
      |> merge_map(map_field(settings_lifecycle, :state_phase_map))
      |> merge_map(map_field(type_workflow, :state_phase_map))
      |> merge_map(map_field(issue_workflow, :state_phase_map))
      |> WorkflowLifecycle.normalize_state_phase_map()

    %{
      raw_state_by_route_key: raw_state_by_route_key,
      policy_by_route_key: policy_by_route_key,
      state_phase_map: state_phase_map
    }
  end

  defp workflow_for_type(_lifecycle, nil), do: %{}

  defp workflow_for_type(lifecycle, workitem_type_id) do
    lifecycle
    |> map_field(:workflows_by_type)
    |> map_field(to_string(workitem_type_id))
    |> normalize_map()
  end

  defp capabilities(profile_context, route_facts, opts) do
    profile_module = profile_context.module
    profile_options = profile_context.options

    profile_required =
      profile_module
      |> ProfileRegistry.required_capabilities(profile_options)
      |> normalize_capability_list()

    conditional =
      route_required_capabilities(profile_context, route_facts)

    required =
      (profile_required ++ conditional)
      |> Enum.uniq()

    optional =
      profile_module
      |> ProfileRegistry.optional_capabilities(profile_options)
      |> normalize_capability_list()

    available = available_capabilities(opts)
    capability_check_requested? = capability_check_requested?(opts)
    missing = if capability_check_requested?, do: missing_capabilities(required, available), else: []

    %{
      "required" => required,
      "optional" => optional,
      "conditional" => conditional,
      "available" => MapSet.to_list(available),
      "missing" => missing,
      "checked" => capability_check_requested?
    }
  end

  defp route_required_capabilities(_profile_context, nil), do: []

  defp route_required_capabilities(profile_context, %RouteFacts{
         action: :dispatch,
         execution_profile: execution_profile
       })
       when is_binary(execution_profile) do
    profile_context
    |> ExecutionProfileRegistry.required_capabilities(execution_profile, :dispatch)
    |> normalize_capability_list()
    |> Enum.uniq()
  end

  defp route_required_capabilities(_profile_context, _route_facts), do: []

  defp available_capabilities(opts) do
    opts
    |> opt(:available_capabilities, [])
    |> normalize_capability_list()
    |> MapSet.new()
  end

  defp missing_capabilities(required, available) do
    Enum.reject(required, &MapSet.member?(available, &1))
  end

  defp capability_check_requested?(opts) do
    opts
    |> opt(:available_capabilities, nil)
    |> is_nil()
    |> Kernel.not()
  end

  defp completion_contract(issue, profile_context) do
    contract =
      case workflow_value(issue, :completion_contract) do
        contract when is_map(contract) ->
          contract

        _contract ->
          ProfileRegistry.completion_contract(profile_context.module, profile_context.options)
      end

    @empty_contract
    |> Map.merge(%{
      "required_outputs" => contract |> map_field(:required_outputs) |> string_list(),
      "allowed_completion_routes" => contract |> map_field(:allowed_completion_routes) |> string_list(),
      "evidence_requirements" => contract |> map_field(:evidence_requirements) |> string_list(),
      "handoff_expectations" => contract |> map_field(:handoff_expectations) |> string_list()
    })
  end

  defp profile_map(profile_context) do
    %{
      "kind" => profile_context.kind,
      "version" => profile_context.version,
      "options" => profile_context.options
    }
  end

  defp route_map(nil), do: @empty_route

  defp route_map(%RouteFacts{} = route_facts) do
    @empty_route
    |> Map.merge(%{
      "key" => atom_name(route_facts.route_key),
      "raw_state" => route_facts.raw_state,
      "lifecycle_phase" => route_facts.lifecycle_phase,
      "action" => atom_name(route_facts.action),
      "transition_target" => atom_name(route_facts.transition_target),
      "execution_profile" => route_facts.execution_profile,
      "policy" => route_facts |> RouteFacts.policy_map() |> route_policy_map()
    })
  end

  defp route_policy_map(policy) when is_map(policy) do
    policy
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), route_policy_value(value))
    end)
  end

  defp route_policy_value(value) when is_atom(value), do: Atom.to_string(value)
  defp route_policy_value(value), do: value

  defp no_route_gate do
    %{
      "status" => "blocked",
      "gate" => "route",
      "category" => "workflow",
      "reason" => "Current issue state does not resolve to a workflow route.",
      "required_evidence" => ["state maps to a profile route key"],
      "observed_evidence" => []
    }
  end

  defp merge_gate(route_facts, capabilities, evidence) do
    evidence =
      evidence
      |> normalize_map()
      |> put_route_evidence(route_facts)

    result = CompletionValidator.merge_gate(evidence, capabilities)
    passed? = Map.get(result, "status") == "passed"

    %{
      "status" => if(passed?, do: "open", else: "blocked"),
      "gate" => "merge",
      "category" => "repo",
      "reason" => merge_gate_reason(passed?),
      "required_evidence" => Map.get(result, "missing_evidence", []),
      "observed_evidence" => observed_route_evidence(route_facts) ++ Map.get(result, "observed_evidence", []),
      "checks" => Map.get(result, "checks", [])
    }
  end

  defp dispatch_gate(route_facts) do
    %{
      "status" => "open",
      "gate" => "dispatch",
      "category" => "workflow",
      "reason" => "Route policy allows automatic dispatch.",
      "required_evidence" => ["route policy action is dispatch"],
      "observed_evidence" => observed_route_evidence(route_facts)
    }
  end

  defp observed_route_evidence(%RouteFacts{} = route_facts) do
    [
      evidence("route", atom_name(route_facts.route_key)),
      evidence("raw_state", route_facts.raw_state),
      evidence("lifecycle_phase", route_facts.lifecycle_phase),
      evidence("action", atom_name(route_facts.action)),
      evidence("execution_profile", route_facts.execution_profile)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp evidence(_key, nil), do: nil
  defp evidence(key, value), do: "#{key}=#{value}"

  defp merge_gate_reason(true), do: "Merge execution route is open and required merge evidence is present."

  defp merge_gate_reason(false),
    do: "Merge execution is fail-closed until change proposal, approval, checks, merge capability, and tracker-state evidence are present."

  defp put_route_evidence(evidence, %RouteFacts{} = route_facts) when is_map(evidence) do
    Map.put(evidence, "route", %{
      "key" => atom_name(route_facts.route_key),
      "current" => atom_name(route_facts.route_key),
      "action" => atom_name(route_facts.action),
      "raw_state" => route_facts.raw_state,
      "lifecycle_phase" => route_facts.lifecycle_phase,
      "execution_profile" => route_facts.execution_profile
    })
  end

  defp completion_evidence(issue, opts) when is_map(issue) do
    opts_evidence = opt(opts, :evidence)

    cond do
      is_map(opts_evidence) -> opts_evidence
      is_map(workflow_value(issue, :completion_evidence)) -> workflow_value(issue, :completion_evidence)
      is_map(workflow_value(issue, :evidence)) -> workflow_value(issue, :evidence)
      true -> %{}
    end
  end

  defp raw_state_for_route_key(workflow, route_key) do
    workflow
    |> Map.get(:raw_state_by_route_key, %{})
    |> RoutePolicy.raw_state_for_route_key(route_key)
  end

  defp policy_for_route_key(policy_by_route_key, route_key)
       when is_map(policy_by_route_key) and is_atom(route_key) do
    Map.get(policy_by_route_key, route_key) ||
      Map.get(policy_by_route_key, Atom.to_string(route_key)) ||
      %{action: :dispatch}
  end

  defp policy_for_route_key(_policy_by_route_key, _route_key), do: %{action: :dispatch}

  defp resolve_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module) do
    RoutePolicy.resolve_policy_by_route_key(policy_by_route_key, base_policy_by_route_key, profile_module)
  end

  defp merge_raw_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module)
       when is_map(base_raw_state_by_route_key) do
    Enum.reduce(profile_module.route_keys(), base_raw_state_by_route_key, fn route_key, acc ->
      case raw_state_by_route_key |> map_field(route_key) |> normalize_string() do
        nil -> acc
        raw_state -> Map.put(acc, route_key, raw_state)
      end
    end)
  end

  defp merge_map(base, value) when is_map(base) and is_map(value), do: Map.merge(base, value)
  defp merge_map(base, _value) when is_map(base), do: base

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_capability_list(%MapSet{} = capabilities) do
    capabilities
    |> MapSet.to_list()
    |> normalize_capability_list()
  end

  defp normalize_capability_list(capabilities) do
    capabilities
    |> List.wrap()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp string_list(values) do
    values
    |> List.wrap()
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value) and not is_boolean(value), do: Atom.to_string(value)
  defp normalize_string(_value), do: nil

  defp workflow_value(issue, key) when is_map(issue) and is_atom(key) do
    issue
    |> map_field(:workflow)
    |> map_field(key)
  end

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_list(opts) and is_atom(key), do: Keyword.get(opts, key, default)

  defp opt(opts, key, default) when is_map(opts) and is_atom(key) do
    map_field(opts, key) || default
  end

  defp opt(_opts, _key, default), do: default

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  defp map_field(_map, _key), do: nil

  defp atom_name(nil), do: nil
  defp atom_name(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_name(value), do: value
end
