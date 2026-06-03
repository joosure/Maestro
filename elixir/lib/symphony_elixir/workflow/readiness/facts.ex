defmodule SymphonyElixir.Workflow.Readiness.Facts do
  @moduledoc """
  Builds structured workflow facts for route readiness, gates, and prompt
  rendering.

  This module is deliberately pure: it summarizes the resolved workflow
  contract and any caller-supplied evidence, but it does not perform tracker,
  repository, or provider side effects.
  """

  alias SymphonyElixir.Workflow.CapabilityNames
  alias SymphonyElixir.Workflow.CompletionValidator
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.RouteFacts
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RoutePolicy.Policy

  @key_key ReadinessContract.key_key()
  @profile_key ReadinessContract.profile_key()
  @route_key ReadinessContract.route_key()
  @required_outputs_key ReadinessContract.required_outputs_key()
  @allowed_completion_routes_key ReadinessContract.allowed_completion_routes_key()
  @evidence_requirements_key ReadinessContract.evidence_requirements_key()
  @handoff_expectations_key ReadinessContract.handoff_expectations_key()

  @empty_route %{
    @key_key => nil,
    "raw_state" => nil,
    "lifecycle_phase" => nil,
    "action" => nil,
    "transition_target" => nil,
    "execution_profile" => nil,
    "policy" => %{}
  }

  @empty_contract %{
    @required_outputs_key => [],
    @allowed_completion_routes_key => [],
    @evidence_requirements_key => [],
    @handoff_expectations_key => []
  }

  @spec facts(map(), keyword() | map()) :: map()
  def facts(issue, opts \\ [])

  def facts(issue, opts) when is_map(issue) do
    profile_context = profile_context(issue, opts)
    route_facts = route_facts(issue, profile_context, opts)
    capabilities = capabilities(profile_context, route_facts, opts)
    evidence = completion_evidence(issue, opts)

    %{
      @profile_key => profile_map(profile_context),
      @route_key => route_map(route_facts),
      "completion_contract" => completion_contract(issue, profile_context),
      "capabilities" => capabilities,
      ReadinessContract.gate_key() => gate(route_facts, capabilities, evidence)
    }
  end

  def facts(_issue, opts) do
    profile_context = profile_context(%{}, opts)
    capabilities = capabilities(profile_context, nil, opts)

    %{
      @profile_key => profile_map(profile_context),
      @route_key => @empty_route,
      "completion_contract" => completion_contract(%{}, profile_context),
      "capabilities" => capabilities,
      ReadinessContract.gate_key() => no_route_gate()
    }
  end

  @spec gate(RouteFacts.t() | nil, map()) :: map()
  def gate(route_facts, capabilities), do: gate(route_facts, capabilities, %{})

  defp gate(route_facts, capabilities, evidence)

  defp gate(_route_facts, %{"missing" => missing}, _evidence) when is_list(missing) and missing != [] do
    gate_map(
      ReadinessContract.blocked(),
      ReadinessContract.capability_gate(),
      "system",
      "Required workflow capabilities are unavailable.",
      missing,
      []
    )
  end

  defp gate(nil, _capabilities, _evidence), do: no_route_gate()

  defp gate(%RouteFacts{action: :wait, route_key: route_key, lifecycle_phase: lifecycle_phase} = route_facts, _capabilities, _evidence) do
    approval_gate? = route_key == :review
    human_review_gate? = WorkflowLifecycle.human_review_phase?(lifecycle_phase)

    cond do
      approval_gate? ->
        gate_map(
          ReadinessContract.waiting(),
          ReadinessContract.approval_gate(),
          "human",
          "Waiting for human approval or review feedback.",
          [
            "human approval or requested-changes decision",
            "tracker or change-proposal review evidence"
          ],
          observed_route_evidence(route_facts)
        )

      human_review_gate? ->
        gate_map(
          ReadinessContract.waiting(),
          ReadinessContract.human_review_gate(),
          "human",
          "Waiting for a human review decision.",
          ["human review decision"],
          observed_route_evidence(route_facts)
        )

      true ->
        gate_map(
          ReadinessContract.waiting(),
          ReadinessContract.route_wait_gate(),
          "workflow",
          "Route policy is wait; automatic dispatch is not allowed.",
          ["route moves to a dispatchable state"],
          observed_route_evidence(route_facts)
        )
    end
  end

  defp gate(%RouteFacts{action: :stop} = route_facts, _capabilities, _evidence) do
    gate_map(
      ReadinessContract.blocked(),
      ReadinessContract.terminal_gate(),
      "workflow",
      "Route policy is stop; no automatic dispatch is allowed.",
      ["new non-terminal route before more work can run"],
      observed_route_evidence(route_facts)
    )
  end

  defp gate(%RouteFacts{action: :disabled} = route_facts, _capabilities, _evidence) do
    gate_map(
      ReadinessContract.blocked(),
      ReadinessContract.route_wait_gate(),
      "workflow",
      "Route policy is disabled; automatic dispatch is not allowed.",
      ["route moves to an enabled state"],
      observed_route_evidence(route_facts)
    )
  end

  defp gate(%RouteFacts{action: :dispatch, route_key: :merging} = route_facts, capabilities, evidence) do
    merge_gate(route_facts, capabilities, evidence)
  end

  defp gate(%RouteFacts{action: :dispatch, execution_profile: execution_profile} = route_facts, capabilities, evidence)
       when is_binary(execution_profile) do
    if capabilities |> Map.get("conditional", []) |> CapabilityNames.merge_gate?() do
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
    gate_map(
      ReadinessContract.open(),
      ReadinessContract.route_preparation_gate(),
      "workflow",
      "Backend route preparation must complete before normal dispatch.",
      ["tracker state moved to the transition target route"],
      observed_route_evidence(route_facts)
    )
  end

  defp gate(%RouteFacts{} = route_facts, _capabilities, _evidence) do
    gate_map(
      ReadinessContract.blocked(),
      ReadinessContract.unknown_route_action_gate(),
      "workflow",
      "Route policy action is not recognized by readiness facts.",
      ["valid route policy action"],
      observed_route_evidence(route_facts)
    )
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
        |> route_policy_for(route_key)
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

    policy_by_route_key =
      ProfileRegistry.default_policy_by_route_key(profile_module, profile_options)
      |> resolve_policy_by_route_key(map_field(settings_lifecycle, :policy_by_route_key), profile_module)
      |> resolve_policy_by_route_key(map_field(type_workflow, :policy_by_route_key), profile_module)
      |> merge_effective_policy_by_route_key(map_field(issue_workflow, :policy_by_route_key), profile_module)

    raw_state_by_route_key =
      RoutePolicy.identity_raw_state_by_route_key(profile_module)
      |> resolve_raw_state_by_route_key(map_field(settings_lifecycle, :raw_state_by_route_key), profile_module, policy_by_route_key)
      |> resolve_raw_state_by_route_key(map_field(type_workflow, :raw_state_by_route_key), profile_module, policy_by_route_key)
      |> merge_effective_raw_state_by_route_key(map_field(issue_workflow, :raw_state_by_route_key), profile_module, policy_by_route_key)
      |> RoutePolicy.remove_disabled_raw_states(policy_by_route_key, profile_module)

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
      @required_outputs_key => contract |> map_field(:required_outputs) |> string_list(),
      @allowed_completion_routes_key => contract |> map_field(:allowed_completion_routes) |> string_list(),
      @evidence_requirements_key => contract |> map_field(:evidence_requirements) |> string_list(),
      @handoff_expectations_key => contract |> map_field(:handoff_expectations) |> string_list()
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
      @key_key => atom_name(route_facts.route_key),
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
    gate_map(
      ReadinessContract.blocked(),
      ReadinessContract.route_gate(),
      "workflow",
      "Current issue state does not resolve to a workflow route.",
      ["state maps to a profile route key"],
      []
    )
  end

  defp merge_gate(route_facts, capabilities, evidence) do
    evidence =
      evidence
      |> normalize_map()
      |> put_route_evidence(route_facts)

    result = CompletionValidator.merge_gate(evidence, capabilities)
    passed? = ReadinessContract.passed?(result)

    gate_map(
      if(passed?, do: ReadinessContract.open(), else: ReadinessContract.blocked()),
      ReadinessContract.merge_gate(),
      "repo",
      merge_gate_reason(passed?),
      Map.get(result, ReadinessContract.missing_evidence_key(), []),
      observed_route_evidence(route_facts) ++ Map.get(result, ReadinessContract.observed_evidence_key(), []),
      %{ReadinessContract.checks_key() => Map.get(result, ReadinessContract.checks_key(), [])}
    )
  end

  defp dispatch_gate(route_facts) do
    gate_map(
      ReadinessContract.open(),
      ReadinessContract.dispatch_gate(),
      "workflow",
      "Route policy allows automatic dispatch.",
      ["route policy action is dispatch"],
      observed_route_evidence(route_facts)
    )
  end

  defp gate_map(status, gate, category, reason, required_evidence, observed_evidence, extra \\ %{}) do
    %{
      ReadinessContract.status_key() => status,
      ReadinessContract.gate_key() => gate,
      ReadinessContract.category_key() => category,
      ReadinessContract.reason_key() => reason,
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
    |> Map.merge(extra)
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
    Map.put(evidence, @route_key, %{
      @key_key => atom_name(route_facts.route_key),
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

  defp route_policy_for(policy_by_route_key, route_key) do
    case RoutePolicy.policy_for_route_key(policy_by_route_key, route_key) do
      policy when is_map(policy) and map_size(policy) > 0 -> policy
      _policy -> %{action: :dispatch}
    end
  end

  defp resolve_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module) do
    RoutePolicy.resolve_policy_by_route_key(policy_by_route_key, base_policy_by_route_key, profile_module)
  end

  defp merge_effective_policy_by_route_key(base_policy_by_route_key, policy_by_route_key, profile_module) do
    RoutePolicy.merge_effective_policy_by_route_key(policy_by_route_key, base_policy_by_route_key, profile_module)
  end

  defp resolve_raw_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module, policy_by_route_key) do
    RoutePolicy.resolve_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, policy_by_route_key)
  end

  defp merge_effective_raw_state_by_route_key(base_raw_state_by_route_key, raw_state_by_route_key, profile_module, policy_by_route_key) do
    RoutePolicy.merge_effective_raw_state_by_route_key(raw_state_by_route_key, base_raw_state_by_route_key, profile_module, policy_by_route_key)
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
