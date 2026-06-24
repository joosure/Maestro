defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.StructuredPlanReviewHandoff do
  @moduledoc """
  Optional structured execution plan checks for coding PR review handoff.

  These checks are disabled by default. When enabled, they consume only the
  canonical structured plan store and structured readiness observations; rendered
  Workpad text is never parsed as authority.
  """

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract
  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract, as: StateTransitionReadinessContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Contract, as: StructuredPlanContract
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Reconciler
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @enabled_gate "workflow.structured_execution_plan.enabled"
  @review_handoff_gate "workflow.structured_execution_plan.review_handoff_required"

  @schema StructuredPlanContract.schema_id()
  @status_key EvidenceContract.status_key()
  @reason_code_key StateTransitionReadinessContract.reason_code_key()
  @repo_key EvidenceContract.repo_key()
  @change_proposal_key EvidenceContract.change_proposal_key()
  @head_sha_key EvidenceContract.head_sha_key()
  @published_head_sha_key EvidenceContract.published_head_sha_key()
  @passed_status StateTransitionReadinessContract.passed_status()
  @missing_status StateTransitionReadinessContract.missing_status()
  @failed_status StateTransitionReadinessContract.failed_status()
  @stale_status StateTransitionReadinessContract.stale_status()

  @allowed_plan_statuses ~w(active handoff_ready)
  @criticalities ~w(handoff_blocking profile_required)
  @repo_change_kinds ~w(repo_push repo_commit)

  @plan_check_key "structured_execution_plan"

  @categories [
    %{
      key: "structured_plan_implementation",
      missing: "structured_plan_implementation_missing",
      incomplete: "structured_plan_implementation_incomplete",
      stale: "structured_plan_implementation_stale",
      evidence_kinds: ~w(repo_commit repo_push),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_validation",
      missing: "structured_plan_validation_missing",
      incomplete: "structured_plan_validation_incomplete",
      stale: "structured_plan_validation_stale",
      evidence_kinds: ~w(repo_diff),
      stale_after_repo?: true,
      head_bound?: true
    },
    %{
      key: "structured_plan_change_proposal",
      missing: "structured_plan_change_proposal_missing",
      incomplete: "structured_plan_change_proposal_incomplete",
      stale: "structured_plan_change_proposal_stale",
      evidence_kinds: ~w(repo_create_or_update_change_proposal repo_change_proposal_snapshot),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_tracker_linkage",
      missing: "structured_plan_tracker_linkage_missing",
      incomplete: "structured_plan_tracker_linkage_incomplete",
      stale: "structured_plan_tracker_linkage_stale",
      evidence_kinds: ~w(tracker_attach_change_proposal),
      stale_after_repo?: false,
      head_bound?: false
    },
    %{
      key: "structured_plan_change_proposal_checks",
      missing: "structured_plan_change_proposal_checks_missing",
      incomplete: "structured_plan_change_proposal_checks_incomplete",
      stale: "structured_plan_change_proposal_checks_stale",
      evidence_kinds: ~w(repo_read_change_proposal_checks),
      stale_after_repo?: true,
      head_bound?: true
    },
    %{
      key: "structured_plan_feedback",
      missing: "structured_plan_feedback_missing",
      incomplete: "structured_plan_feedback_incomplete",
      stale: "structured_plan_feedback_stale",
      evidence_kinds: ~w(repo_read_change_proposal_discussion),
      stale_after_repo?: true,
      head_bound?: false
    },
    %{
      key: "structured_plan_handoff_record",
      missing: "structured_plan_handoff_record_missing",
      incomplete: "structured_plan_handoff_record_incomplete",
      stale: "structured_plan_handoff_record_stale",
      evidence_kinds: ~w(tracker_upsert_workpad),
      stale_after_repo?: true,
      head_bound?: false
    }
  ]

  @spec checks(map() | struct() | nil, map(), map(), keyword()) :: [map()]
  def checks(workflow, issue, observations, opts) when is_map(issue) and is_map(observations) and is_list(opts) do
    case gate_state(opts) do
      :disabled ->
        []

      {:misconfigured, reason} ->
        [failed_check(@plan_check_key, "structured_plan_gate_misconfigured", reason, [])]

      :enabled ->
        plan_checks(workflow, issue, observations, opts)
    end
  end

  def checks(_workflow, _issue, _observations, _opts), do: []

  defp gate_state(opts) do
    structured_enabled? = gate_enabled?(opts, @enabled_gate, :enabled)
    review_handoff_required? = gate_enabled?(opts, @review_handoff_gate, :review_handoff_required)

    cond do
      review_handoff_required? and structured_enabled? ->
        :enabled

      review_handoff_required? ->
        {:misconfigured, "Structured plan review handoff requires structured execution plans to be enabled."}

      true ->
        :disabled
    end
  end

  defp gate_enabled?(opts, gate_key, config_key) do
    gates = Keyword.get(opts, :gates, StructuredPlanContract.gate_defaults())
    config = structured_plan_opts(opts)

    gate_value(gates, gate_key) == true or
      option_value(config, gate_key) == true or
      option_value(config, config_key) == true
  end

  defp gate_value(gates, gate_key) when is_map(gates), do: Map.get(gates, gate_key)
  defp gate_value(_gates, _gate_key), do: nil

  defp plan_checks(workflow, issue, observations, opts) do
    case fetch_plan(workflow, issue, opts) do
      {:ok, plan, context} ->
        case plan_scope_check(plan, context, observations) do
          {:ok, plan_check} -> [plan_check | category_checks(plan)]
          {:error, plan_check} -> [plan_check]
        end

      {:error, %{code: "store_unavailable"} = reason} ->
        [failed_check(@plan_check_key, "structured_plan_store_unavailable", "Canonical structured execution plan store is unavailable.", observed_error(reason))]

      {:error, reason} ->
        [missing_check(@plan_check_key, "structured_plan_missing", "A canonical structured execution plan is required.", observed_error(reason))]
    end
  end

  defp fetch_plan(workflow, issue, opts) do
    config = structured_plan_opts(opts)
    store_opts = store_opts(opts)
    context = plan_context(workflow, issue, opts, config)

    case option_value(config, :plan_id) do
      plan_id when is_binary(plan_id) ->
        with {:ok, plan} <- Store.fetch(plan_id, store_opts), do: {:ok, plan, context}

      _plan_id ->
        with {:ok, run_id} <- required_context(context, :run_id),
             {:ok, profile} <- required_context(context, :workflow_profile),
             {:ok, route_key} <- required_context(context, :route_key),
             {:ok, plan} <- Store.active_plan(run_id, profile, route_key, store_opts) do
          {:ok, plan, context}
        end
    end
  end

  defp required_context(context, key) do
    case Map.get(context, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      %{"kind" => kind, "version" => version} = profile when is_binary(kind) and is_integer(version) -> {:ok, profile}
      _value -> {:error, %{code: "structured_plan_context_missing", missing: Atom.to_string(key)}}
    end
  end

  defp plan_context(workflow, issue, opts, config) do
    %{
      run_id: option_value(config, :run_id) || Keyword.get(opts, :run_id) || runtime_value(opts, :run_id),
      issue_ids: issue_ids(issue, opts, config),
      route_key: option_value(config, :route_key) || "developing",
      workflow_profile: option_value(config, :workflow_profile) || workflow_profile(workflow)
    }
  end

  defp workflow_profile(workflow) do
    case {profile_kind(workflow), profile_version(workflow)} do
      {kind, version} when is_binary(kind) and is_integer(version) -> %{"kind" => kind, "version" => version}
      _profile -> nil
    end
  end

  defp plan_scope_check(plan, context, observations) do
    cond do
      Map.get(plan, "status") == "superseded" ->
        {:error, failed_check(@plan_check_key, "structured_plan_superseded", "Superseded structured execution plans cannot satisfy review handoff.", observed_plan(plan))}

      Map.get(plan, "status") == "closed" ->
        {:error, failed_check(@plan_check_key, "structured_plan_closed", "Closed structured execution plans cannot satisfy review handoff.", observed_plan(plan))}

      Map.get(plan, "status") not in @allowed_plan_statuses ->
        {:error, failed_check(@plan_check_key, "structured_plan_not_ready", "Structured execution plan must be active or handoff_ready.", observed_plan(plan))}

      Map.get(plan, "run_id") != Map.get(context, :run_id) ->
        {:error, failed_check(@plan_check_key, "structured_plan_cross_run", "Structured execution plan belongs to a different run.", observed_plan(plan))}

      not issue_matches?(plan, Map.get(context, :issue_ids, [])) ->
        {:error, failed_check(@plan_check_key, "structured_plan_scope_mismatch", "Structured execution plan belongs to a different issue.", observed_plan(plan))}

      not profile_matches?(plan, Map.get(context, :workflow_profile)) ->
        {:error, failed_check(@plan_check_key, "structured_plan_scope_mismatch", "Structured execution plan belongs to a different workflow profile.", observed_plan(plan))}

      route_key_mismatch?(plan, Map.get(context, :route_key)) ->
        {:error, failed_check(@plan_check_key, "structured_plan_scope_mismatch", "Structured execution plan belongs to a different route.", observed_plan(plan))}

      head_mismatch?(latest_repo_head(plan), current_head(observations)) ->
        {:error, stale_check(@plan_check_key, "structured_plan_head_mismatch", "Structured execution plan head does not match the latest readiness head.", observed_plan(plan))}

      true ->
        {:ok, passed_check(@plan_check_key, observed_plan(plan))}
    end
  end

  defp category_checks(plan), do: Enum.map(@categories, &category_check(plan, &1))

  defp category_check(plan, category) do
    items = critical_items(plan, Map.fetch!(category, :evidence_kinds))

    cond do
      items == [] ->
        missing_check(Map.fetch!(category, :key), Map.fetch!(category, :missing), "A critical structured plan item is required for this readiness fact.", [])

      Enum.all?(items, &item_ready?(&1, plan, category)) ->
        passed_check(Map.fetch!(category, :key), observed_category(items, category))

      Enum.any?(items, &item_stale?(&1, plan, category)) ->
        stale_check(Map.fetch!(category, :key), Map.fetch!(category, :stale), "Structured plan evidence is older than the latest repository change.", observed_category(items, category))

      true ->
        failed_check(Map.fetch!(category, :key), Map.fetch!(category, :incomplete), "Critical structured plan item evidence is incomplete.", observed_category(items, category))
    end
  end

  defp critical_items(plan, evidence_kinds) do
    plan
    |> Map.get("items", [])
    |> Enum.filter(fn item ->
      is_map(item) and Map.get(item, "required") == true and Map.get(item, "criticality") in @criticalities and
        item_evidence_kinds(item) |> Enum.any?(&(&1 in evidence_kinds))
    end)
  end

  defp item_ready?(item, plan, category) do
    Map.get(item, "status") == "complete" and
      Reconciler.satisfied?(item) and
      not item_stale?(item, plan, category) and
      not item_head_mismatch?(item, plan, category)
  end

  defp item_stale?(item, plan, %{stale_after_repo?: true} = category) do
    refs = category_refs(item, Map.fetch!(category, :evidence_kinds))
    refs != [] and newer_than?(latest_repo_change_at(plan), latest_observed_at(refs))
  end

  defp item_stale?(_item, _plan, _category), do: false

  defp item_head_mismatch?(item, plan, %{head_bound?: true} = category) do
    latest_repo_head = latest_repo_head(plan)

    item
    |> category_refs(Map.fetch!(category, :evidence_kinds))
    |> Enum.any?(fn ref -> head_mismatch?(payload_head(ref), latest_repo_head) end)
  end

  defp item_head_mismatch?(_item, _plan, _category), do: false

  defp category_refs(item, evidence_kinds) do
    item
    |> Map.get("evidence_refs", [])
    |> Enum.filter(&(Map.get(&1, "evidence_kind") in evidence_kinds))
  end

  defp item_evidence_kinds(item) do
    item
    |> Map.get("evidence_requirements", [])
    |> Enum.flat_map(fn
      %{"evidence_kind" => evidence_kind} when is_binary(evidence_kind) -> [evidence_kind]
      _requirement -> []
    end)
  end

  defp latest_repo_head(plan) do
    plan
    |> all_evidence_refs()
    |> Enum.filter(&(Map.get(&1, "evidence_kind") in @repo_change_kinds))
    |> latest_ref()
    |> payload_head()
  end

  defp latest_repo_change_at(plan) do
    plan
    |> all_evidence_refs()
    |> Enum.filter(&(Map.get(&1, "evidence_kind") in @repo_change_kinds))
    |> latest_observed_at()
  end

  defp all_evidence_refs(plan) do
    plan
    |> Map.get("items", [])
    |> Enum.flat_map(fn
      %{"evidence_refs" => refs} when is_list(refs) -> refs
      _item -> []
    end)
  end

  defp latest_ref(refs) do
    Enum.max_by(refs, &observed_at_unix/1, fn -> nil end)
  end

  defp latest_observed_at(refs) do
    refs
    |> Enum.flat_map(fn ref ->
      case parse_datetime(Map.get(ref, "observed_at")) do
        %DateTime{} = datetime -> [datetime]
        nil -> []
      end
    end)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  defp observed_at_unix(ref) do
    case parse_datetime(Map.get(ref || %{}, "observed_at")) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
      nil -> -1
    end
  end

  defp newer_than?(nil, _right), do: false
  defp newer_than?(_left, nil), do: false
  defp newer_than?(left, right), do: DateTime.compare(left, right) == :gt

  defp current_head(observations) when is_map(observations) do
    repo = Map.get(observations, @repo_key, %{})
    change_proposal = Map.get(observations, @change_proposal_key, %{})

    Map.get(repo, @published_head_sha_key) ||
      Map.get(repo, @head_sha_key) ||
      Map.get(change_proposal, @head_sha_key)
  end

  defp payload_head(%{"payload" => payload}) when is_map(payload) do
    Map.get(payload, @published_head_sha_key) || Map.get(payload, @head_sha_key)
  end

  defp payload_head(_ref), do: nil

  defp head_mismatch?(left, right), do: present?(left) and present?(right) and left != right

  defp issue_matches?(plan, issue_ids) when is_list(issue_ids) do
    issue_ids = Enum.uniq(issue_ids)

    issue_ids == [] or
      Map.get(plan, "issue_id") in issue_ids or
      Map.get(plan, "issue_identifier") in issue_ids
  end

  defp profile_matches?(plan, %{"kind" => kind, "version" => version}) do
    get_in(plan, ["workflow_profile", "kind"]) == kind and get_in(plan, ["workflow_profile", "version"]) == version
  end

  defp profile_matches?(_plan, _profile), do: true

  defp route_key_mismatch?(_plan, nil), do: false
  defp route_key_mismatch?(plan, route_key), do: Map.get(plan, "route_key") != route_key

  defp passed_check(key, observed), do: check(key, @passed_status, nil, observed, observed)

  defp missing_check(key, reason_code, detail, observed), do: check(key, @missing_status, reason_code, detail, observed)

  defp failed_check(key, reason_code, detail, observed), do: check(key, @failed_status, reason_code, detail, observed)

  defp stale_check(key, reason_code, detail, observed), do: check(key, @stale_status, reason_code, detail, observed)

  defp check(key, status, reason_code, required_evidence, observed_evidence) do
    %{
      ReadinessContract.key_key() => key,
      @status_key => status,
      @reason_code_key => reason_code,
      ReadinessContract.required_evidence_key() => required_evidence,
      ReadinessContract.observed_evidence_key() => observed_evidence
    }
    |> drop_nil_values()
  end

  defp observed_plan(plan) when is_map(plan) do
    [
      @schema,
      if(present?(Map.get(plan, "plan_id")), do: "#{@schema}.plan_id"),
      if(present?(Map.get(plan, "status")), do: "#{@schema}.status=#{Map.get(plan, "status")}"),
      if(present?(latest_repo_head(plan)), do: "#{@schema}.head_sha")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp observed_category(items, category) do
    evidence_kinds = Map.fetch!(category, :evidence_kinds)

    items
    |> Enum.flat_map(fn item ->
      refs = category_refs(item, evidence_kinds)

      [
        "#{@schema}.item=#{Map.get(item, "item_id")}",
        "#{@schema}.item_status=#{Map.get(item, "status")}",
        "#{@schema}.#{Map.fetch!(category, :key)}.evidence_refs=#{length(refs)}"
      ]
    end)
    |> Enum.uniq()
  end

  defp observed_error(%{code: code}) when is_binary(code), do: ["#{@schema}.error=#{code}"]
  defp observed_error(%{code: code}) when is_atom(code), do: ["#{@schema}.error=#{Atom.to_string(code)}"]
  defp observed_error(_reason), do: []

  defp store_opts(opts) do
    config = structured_plan_opts(opts)

    []
    |> maybe_put(:server, option_value(config, :server) || Keyword.get(opts, :structured_execution_plan_store))
  end

  defp structured_plan_opts(opts), do: Keyword.get(opts, :structured_execution_plan, %{})

  defp runtime_value(opts, key) do
    runtime_metadata =
      case Keyword.get(opts, :tool_context) do
        %{runtime_metadata: metadata} when is_map(metadata) -> metadata
        %{"runtime_metadata" => metadata} when is_map(metadata) -> metadata
        _context -> %{}
      end

    Keyword.get(opts, key) || Map.get(runtime_metadata, key) || Map.get(runtime_metadata, Atom.to_string(key))
  end

  defp option_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp option_value(map, key) when is_map(map) and is_binary(key), do: Map.get(map, key)
  defp option_value(keyword, key) when is_list(keyword) and is_atom(key), do: Keyword.get(keyword, key)
  defp option_value(_config, _key), do: nil

  defp issue_ids(issue, opts, config) do
    [
      option_value(config, :issue_id),
      option_value(config, :issue_identifier),
      Keyword.get(opts, :issue_key),
      string_value(issue, "id"),
      string_value(issue, "identifier")
    ]
    |> Enum.flat_map(&present_values/1)
    |> Enum.uniq()
  end

  defp profile_kind(%{profile_kind: kind}) when is_binary(kind), do: kind
  defp profile_kind(%{"profile_kind" => kind}) when is_binary(kind), do: kind
  defp profile_kind(%{profile: %{kind: kind}}) when is_binary(kind), do: kind
  defp profile_kind(%{"profile" => %{"kind" => kind}}) when is_binary(kind), do: kind
  defp profile_kind(_workflow), do: nil

  defp profile_version(%{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{"profile_version" => version}) when is_integer(version), do: version
  defp profile_version(%{profile: %{version: version}}) when is_integer(version), do: version
  defp profile_version(%{"profile" => %{"version" => version}}) when is_integer(version), do: version
  defp profile_version(workflow), do: if(profile_kind(workflow) == CodingPrDelivery.kind(), do: CodingPrDelivery.version())

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) || map_get_existing_atom(map, key) do
      value when is_binary(value) -> value
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> Atom.to_string(value)
      _value -> nil
    end
  end

  defp string_value(_map, _key), do: nil

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp present_values(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: value |> Atom.to_string() |> present_values()
  defp present_values(_value), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
