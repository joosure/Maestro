defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoff do
  @moduledoc """
  Backend-owned review handoff gate for `coding_pr_delivery`.

  The validator consumes only structured observations assembled by typed tools,
  backend collectors, and structured tracker attachments. It never parses
  workpad Markdown, comments, headings, or visible checkbox state.
  """

  alias SymphonyElixir.Workflow.Effective
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Readiness.EvidenceContract
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.Profiles.CodingPrDelivery
  alias SymphonyElixir.Workflow.Readiness.Contract, as: ReadinessContract
  alias SymphonyElixir.Workflow.RoutePolicy
  alias SymphonyElixir.Workflow.RouteRef
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract, as: StateTransitionReadinessContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.StructuredPlanReviewHandoff
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policy, as: StateTransitionReadinessPolicy
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  @behaviour StateTransitionReadinessPolicy

  @policy_id ReviewHandoffContract.coding_pr_delivery_policy_id()
  @schema ReviewHandoffContract.schema()
  @schema_key StateTransitionReadinessContract.schema_key()
  @policy_id_key StateTransitionReadinessContract.policy_id_key()
  @observations_key StateTransitionReadinessContract.observations_key()
  @workpad_key EvidenceContract.workpad_key()
  @repo_key EvidenceContract.repo_key()
  @change_proposal_key EvidenceContract.change_proposal_key()
  @validation_key EvidenceContract.validation_key()
  @checks_key EvidenceContract.checks_key()
  @feedback_key EvidenceContract.feedback_key()
  @status_key EvidenceContract.status_key()
  @source_key EvidenceContract.source_key()
  @id_key EvidenceContract.id_key()
  @url_key EvidenceContract.url_key()
  @head_sha_key EvidenceContract.head_sha_key()
  @published_head_sha_key EvidenceContract.published_head_sha_key()
  @commits_key EvidenceContract.commits_key()
  @change_kind_key EvidenceContract.change_kind_key()
  @no_code_change_justification_key EvidenceContract.no_code_change_justification_key()
  @linked_to_tracker_key EvidenceContract.linked_to_tracker_key()
  @observed_at_key EvidenceContract.observed_at_key()
  @updated_at_key EvidenceContract.updated_at_key()
  @commands_key EvidenceContract.commands_key()
  @workpad_id_key EvidenceContract.workpad_id_key()
  @actionable_count_key EvidenceContract.actionable_count_key()
  @remediation_actions_key "remediation_actions"
  @target_state_key StateTransitionReadinessContract.target_state_key()
  @capability_gaps_key StateTransitionReadinessContract.capability_gaps_key()
  @downgrades_key StateTransitionReadinessContract.downgrades_key()
  @error_code_key StateTransitionReadinessContract.error_code_key()
  @reason_code_key StateTransitionReadinessContract.reason_code_key()
  @reason_codes_key StateTransitionReadinessContract.reason_codes_key()
  @code_key StateTransitionReadinessContract.code_key()
  @detail_key StateTransitionReadinessContract.detail_key()
  @passed_status StateTransitionReadinessContract.passed_status()
  @blocked_status StateTransitionReadinessContract.blocked_status()
  @missing_status StateTransitionReadinessContract.missing_status()
  @failed_status StateTransitionReadinessContract.failed_status()
  @stale_status StateTransitionReadinessContract.stale_status()
  @unknown_status StateTransitionReadinessContract.unknown_status()
  @unavailable_status StateTransitionReadinessContract.unavailable_status()
  @not_required_status StateTransitionReadinessContract.not_required_status()
  @linked_status StateTransitionReadinessContract.linked_status()
  @created_status StateTransitionReadinessContract.created_status()
  @updated_status StateTransitionReadinessContract.updated_status()
  @tracker_observed_source StateTransitionReadinessContract.tracker_observed_source()
  @typed_tool_observed_source StateTransitionReadinessContract.typed_tool_observed_source()
  @code_change_kind EvidenceContract.code_change_kind()
  @no_code_change_kind EvidenceContract.no_code_change_kind()
  @review_handoff_not_ready_error ReviewHandoffContract.not_ready_error()
  @change_proposal_path_markers ["/pull/", "/pulls/", "/merge_requests/", "/-/merge_requests/"]
  @passing_change_proposal_statuses ReviewHandoffContract.passing_change_proposal_statuses()
  @passing_check_statuses ReviewHandoffContract.passing_check_statuses()
  @passing_feedback_statuses ReviewHandoffContract.passing_feedback_statuses()
  @passing_workpad_statuses [@created_status, @updated_status]

  @type validation_result :: :ok | {:error, {:review_handoff_not_ready, map()}}

  @impl StateTransitionReadinessPolicy
  @spec policy_id() :: String.t()
  def policy_id, do: @policy_id

  @impl StateTransitionReadinessPolicy
  @spec schema() :: String.t()
  def schema, do: @schema

  @impl StateTransitionReadinessPolicy
  @spec governed_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  def governed_target?(workflow, target_state_name), do: review_target?(workflow, target_state_name)

  @spec review_target?(Effective.t() | map() | nil, String.t() | nil) :: boolean()
  def review_target?(workflow, target_state_name) do
    profile_kind(workflow) == CodingPrDelivery.kind() and
      (route_key_for_state(workflow, target_state_name) == CodingPrDelivery.review_route_key() or
         WorkflowLifecycle.human_review_phase?(lifecycle_phase_for_state(workflow, target_state_name)) or
         logical_review_target?(target_state_name))
  end

  @spec validate(Effective.t() | map() | nil, map(), keyword()) :: validation_result()
  @impl StateTransitionReadinessPolicy
  def validate(workflow, issue, opts \\ [])

  def validate(workflow, issue, opts) when is_map(issue) and is_list(opts) do
    target_state_name = Keyword.get(opts, :target_state_name)

    if review_target?(workflow, target_state_name) do
      evidence = evidence_for_issue(issue, opts)
      result = validate_evidence(workflow, issue, evidence, opts)

      if passed_result?(result) do
        :ok
      else
        {:error, {:review_handoff_not_ready, result}}
      end
    else
      :ok
    end
  end

  def validate(workflow, _issue, opts) do
    target_state_name = Keyword.get(opts, :target_state_name)

    if review_target?(workflow, target_state_name) do
      {:error,
       {:review_handoff_not_ready,
        blocked_result(workflow, target_state_name, [
          missing_check(check_key(:issue_snapshot), reason_code(:issue_snapshot_missing), "Structured tracker issue snapshot is required.", [])
        ])}}
    else
      :ok
    end
  end

  @spec validate_evidence(Effective.t() | map() | nil, map(), map(), keyword()) :: map()
  def validate_evidence(workflow, issue, evidence, opts \\ []) when is_map(issue) and is_map(evidence) do
    target_state_name = Keyword.get(opts, :target_state_name)
    observations = normalized_observations(evidence, issue)
    checks = checks(workflow, issue, observations, opts)

    if Enum.all?(checks, &passed_check?/1) do
      passed_result(workflow, target_state_name, checks)
    else
      blocked_result(workflow, target_state_name, checks)
    end
  end

  defp evidence_for_issue(issue, opts) do
    explicit_evidence = opts |> Keyword.get(:evidence, %{}) |> normalize_evidence()
    run_id = Keyword.get(opts, :run_id)
    issue_keys = issue_keys(issue, Keyword.get(opts, :issue_key))

    scoped_issue_keys =
      run_id
      |> Store.scope_issue_keys(issue_keys)

    issue_keys
    |> Store.snapshot()
    |> deep_merge(Store.snapshot(scoped_issue_keys))
    |> normalize_evidence()
    |> deep_merge(explicit_evidence)
  end

  defp checks(workflow, issue, observations, opts) do
    repo = observation(observations, @repo_key)
    change_proposal = observation(observations, @change_proposal_key)
    validation = observation(observations, @validation_key)
    change_proposal_checks = observation(observations, @checks_key)
    feedback = observation(observations, @feedback_key)
    readiness_observations = [repo, change_proposal, validation, change_proposal_checks, feedback]

    [
      workpad_check(observation(observations, @workpad_key), readiness_observations),
      repo_check(repo),
      validation_check(validation, repo, change_proposal),
      change_proposal_check(workflow, change_proposal),
      checks_check(workflow, change_proposal_checks, repo, change_proposal),
      feedback_check(feedback)
    ] ++ StructuredPlanReviewHandoff.checks(workflow, issue, observations, opts)
  end

  defp workpad_check(workpad, readiness_observations) do
    cond do
      not is_map(workpad) or map_size(workpad) == 0 ->
        missing_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_missing),
          "A backend-observed workpad handoff record is required.",
          observed(workpad, @workpad_key)
        )

      not trusted_workpad_record?(workpad) ->
        failed_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_untrusted),
          "Workpad readiness requires a successful backend-observed workpad write, not agent-declared section completion.",
          observed(workpad, @workpad_key)
        )

      stale_workpad_record?(workpad, readiness_observations) ->
        stale_check(
          check_key(:workpad_recorded),
          reason_code(:workpad_record_stale),
          "The workpad handoff record must be updated after the latest repository, change-proposal, validation, check, or feedback evidence.",
          observed(workpad, @workpad_key)
        )

      true ->
        passed_check(check_key(:workpad_recorded), observed_evidence_code(:workpad_recorded), observed(workpad, @workpad_key))
    end
  end

  defp repo_check(repo) do
    cond do
      not is_map(repo) or map_size(repo) == 0 ->
        missing_check(check_key(:implementation_evidence), reason_code(:repo_implementation_evidence_missing), "Repository implementation evidence is required.", [])

      Map.get(repo, @change_kind_key) == @code_change_kind and code_change_observed?(repo) ->
        passed_check(check_key(:implementation_evidence), observed_evidence_code(:repo_code_change), observed(repo, @repo_key))

      Map.get(repo, @change_kind_key) == @no_code_change_kind and present?(Map.get(repo, @no_code_change_justification_key)) ->
        passed_check(check_key(:implementation_evidence), observed_evidence_code(:repo_no_code_change_justification), observed(repo, @repo_key))

      Map.get(repo, @change_kind_key) == @no_code_change_kind ->
        missing_check(
          check_key(:implementation_evidence),
          reason_code(:repo_no_code_change_justification_missing),
          "No-code-change handoff requires a structured justification.",
          observed(repo, @repo_key)
        )

      true ->
        failed_check(
          check_key(:implementation_evidence),
          reason_code(:repo_implementation_evidence_incomplete),
          "Repository implementation evidence must identify a code change or justified no-code-change path.",
          observed(repo, @repo_key)
        )
    end
  end

  defp validation_check(validation, repo, change_proposal) do
    current_head = current_head(repo, change_proposal)
    validation_head = Map.get(validation || %{}, @head_sha_key) || latest_command_head(validation)

    cond do
      not is_map(validation) or map_size(validation) == 0 ->
        missing_check(check_key(:validation_passed), reason_code(:validation_evidence_missing), "Structured validation command evidence is required.", [])

      Map.get(validation, @status_key) != @passed_status ->
        failed_check(check_key(:validation_passed), reason_code(:validation_not_passed), "Validation evidence must have status passed.", observed(validation, @validation_key))

      stale_head?(validation_head, current_head) ->
        stale_check(
          check_key(:validation_passed),
          reason_code(:validation_head_stale),
          "Validation evidence must be for the latest observed repository or change-proposal head.",
          observed(validation, @validation_key)
        )

      true ->
        passed_check(check_key(:validation_passed), observed_evidence_code(:validation_passed), observed(validation, @validation_key))
    end
  end

  defp change_proposal_check(workflow, change_proposal) do
    if change_proposal_required?(workflow) do
      cond do
        not is_map(change_proposal) or map_size(change_proposal) == 0 ->
          missing_check(
            check_key(:change_proposal_linked),
            reason_code(:change_proposal_evidence_missing),
            "Structured change proposal evidence and tracker linkage are required.",
            []
          )

        Map.get(change_proposal, @status_key) not in @passing_change_proposal_statuses ->
          failed_check(
            check_key(:change_proposal_linked),
            reason_code(:change_proposal_not_ready),
            "Change proposal must be created, updated, or linked.",
            observed(change_proposal, @change_proposal_key)
          )

        Map.get(change_proposal, @linked_to_tracker_key) != true ->
          missing_check(
            check_key(:change_proposal_linked),
            reason_code(:change_proposal_tracker_link_missing),
            "Change proposal must be linked through structured tracker attachment evidence.",
            observed(change_proposal, @change_proposal_key)
          )

        true ->
          passed_check(check_key(:change_proposal_linked), observed_evidence_code(:change_proposal_linked), observed(change_proposal, @change_proposal_key))
      end
    else
      not_required = observed_evidence_code(:change_proposal_not_required)
      passed_check(check_key(:change_proposal_linked), not_required, [not_required])
    end
  end

  defp checks_check(workflow, checks, repo, change_proposal) do
    current_head = current_head(repo, change_proposal)
    checks_head = Map.get(checks || %{}, @head_sha_key)
    checks_status = Map.get(checks || %{}, @status_key)

    cond do
      not is_map(checks) or map_size(checks) == 0 ->
        missing_check(check_key(:change_proposal_checks), reason_code(:change_proposal_checks_evidence_missing), "Change proposal check evidence must be read before review handoff.", [])

      checks_status == @unavailable_status ->
        failed_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_unavailable),
          "Change proposal checks are unavailable and are not configured as not_required.",
          observed(checks, @checks_key)
        )

      checks_status == @unknown_status ->
        failed_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_unknown),
          "Change proposal check status is unknown.",
          observed(checks, @checks_key)
        )

      checks_status not in @passing_check_statuses ->
        failed_check(check_key(:change_proposal_checks), reason_code(:change_proposal_checks_not_passing), "Change proposal checks must be passed or not_required.", observed(checks, @checks_key))

      checks_status == @not_required_status and not change_proposal_checks_not_required?(workflow) ->
        failed_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_absent_without_config),
          "Change proposal checks can be not_required only when trusted workflow profile policy declares them not required.",
          observed(checks, @checks_key)
        )

      checks_status == @not_required_status and stale_observation?(checks, repo, change_proposal) ->
        stale_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_observation_stale),
          "Change proposal check evidence must be observed after the latest repository or change-proposal head evidence.",
          observed(checks, @checks_key)
        )

      checks_status != @not_required_status and stale_head?(checks_head, current_head) ->
        stale_check(
          check_key(:change_proposal_checks),
          reason_code(:change_proposal_checks_head_stale),
          "Change proposal check evidence must match the latest observed repository or change-proposal head.",
          observed(checks, @checks_key)
        )

      true ->
        passed_check(check_key(:change_proposal_checks), observed_evidence_code(:checks_ready), observed(checks, @checks_key))
    end
  end

  defp feedback_check(feedback) do
    cond do
      not is_map(feedback) or map_size(feedback) == 0 ->
        missing_check(check_key(:feedback_clear), reason_code(:feedback_evidence_missing), "Review feedback evidence must be read before review handoff.", [])

      Map.get(feedback, @status_key) not in @passing_feedback_statuses ->
        failed_check(check_key(:feedback_clear), reason_code(:feedback_action_required), "Actionable review feedback must be clear before review handoff.", observed(feedback, @feedback_key))

      integer(Map.get(feedback, @actionable_count_key), 0) > 0 ->
        failed_check(check_key(:feedback_clear), reason_code(:feedback_action_required), "Actionable review feedback must be clear before review handoff.", observed(feedback, @feedback_key))

      true ->
        passed_check(check_key(:feedback_clear), observed_evidence_code(:feedback_clear), observed(feedback, @feedback_key))
    end
  end

  defp passed_result(workflow, target_state_name, checks) do
    base_result(workflow, target_state_name, checks)
    |> Map.put(@status_key, @passed_status)
    |> Map.put(@reason_codes_key, [])
  end

  defp blocked_result(workflow, target_state_name, checks) do
    failed_checks = Enum.reject(checks, &passed_check?/1)

    base_result(workflow, target_state_name, checks)
    |> Map.put(@status_key, @blocked_status)
    |> Map.put(@error_code_key, @review_handoff_not_ready_error)
    |> Map.put(@reason_codes_key, Enum.map(failed_checks, &Map.fetch!(&1, @reason_code_key)))
    |> Map.put(ReadinessContract.missing_evidence_key(), Enum.map(failed_checks, &missing_entry/1))
    |> Map.put(@remediation_actions_key, remediation_actions(failed_checks))
  end

  defp base_result(workflow, target_state_name, checks) do
    %{
      @policy_id_key => @policy_id,
      @schema_key => @schema,
      ReadinessContract.gate_key() => ReadinessContract.human_review_gate(),
      @target_state_key => target_state_name,
      ReadinessContract.checks_key() => checks,
      ReadinessContract.missing_evidence_key() => [],
      ReadinessContract.observed_evidence_key() => observed_evidence(checks),
      @capability_gaps_key => [],
      @downgrades_key => [],
      @remediation_actions_key => []
    }
    |> Map.merge(
      workflow
      |> workflow_profile_ref()
      |> RouteRef.new!(CodingPrDelivery.review_route_key())
      |> RouteRef.string_fields()
    )
    |> drop_nil_values()
  end

  defp passed_check(key, observed_evidence, observed) do
    check(key, @passed_status, nil, observed_evidence, observed)
  end

  defp missing_check(key, reason_code, detail, observed) do
    check(key, @missing_status, reason_code, detail, observed)
  end

  defp failed_check(key, reason_code, detail, observed) do
    check(key, @failed_status, reason_code, detail, observed)
  end

  defp stale_check(key, reason_code, detail, observed) do
    check(key, @stale_status, reason_code, detail, observed)
  end

  defp check_key(key), do: ReviewHandoffContract.check_key(key)
  defp reason_code(key), do: ReviewHandoffContract.reason_code(key)
  defp observed_evidence_code(key), do: ReviewHandoffContract.observed_evidence_code(key)

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

  defp passed_result?(result) when is_map(result), do: Map.get(result, @status_key) == @passed_status

  defp passed_check?(check) when is_map(check), do: Map.get(check, @status_key) == @passed_status
  defp passed_check?(_check), do: false

  defp missing_entry(check) do
    %{
      @code_key => Map.fetch!(check, @reason_code_key),
      @detail_key => Map.fetch!(check, ReadinessContract.required_evidence_key())
    }
  end

  defp remediation_actions(checks) do
    checks
    |> Enum.map(&remediation_action/1)
    |> Enum.uniq()
  end

  defp remediation_action(check) do
    reason_code = Map.fetch!(check, @reason_code_key)
    check_key = Map.fetch!(check, ReadinessContract.key_key())

    {action, capabilities} =
      case check_key do
        "issue_snapshot" ->
          {"Refresh the structured tracker issue snapshot before retrying the review handoff.", ["tracker.issue_snapshot"]}

        "workpad_recorded" ->
          {"Write the final handoff record after the latest repository, PR, checks, and feedback evidence.", ["tracker.upsert_workpad"]}

        "implementation_evidence" ->
          {"Record repository implementation evidence from the repo typed tools before review handoff.", ["repo.commit", "repo.push"]}

        "validation_passed" ->
          {"Record passing validation evidence for the latest pushed head before review handoff.", ["repo.diff"]}

        "change_proposal_linked" ->
          {"Create or refresh the change proposal and attach/link it to the tracker issue.",
           [
             "repo.create_or_update_change_proposal",
             "tracker.attach_change_proposal"
           ]}

        "change_proposal_checks" ->
          {"Read change-proposal checks for the latest change proposal head and wait until they pass or are not required.", ["repo.read_change_proposal_checks"]}

        "feedback_clear" ->
          {"Read provider discussion/review feedback and resolve or explicitly clear all actionable feedback.", ["repo.read_change_proposal_discussion"]}

        _check_key ->
          {"Refresh the missing structured evidence and retry the review handoff.", []}
      end

    %{
      @reason_code_key => reason_code,
      "check" => check_key,
      "action" => action,
      "capabilities" => capabilities
    }
  end

  defp observed_evidence(checks) do
    checks
    |> Enum.flat_map(&List.wrap(Map.get(&1, ReadinessContract.observed_evidence_key())))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalized_observations(evidence, issue) do
    evidence
    |> normalize_evidence()
    |> Map.get(@observations_key, %{})
    |> deep_merge(tracker_issue_observations(issue))
  end

  defp normalize_evidence(%{@observations_key => observations} = evidence) when is_map(observations), do: evidence
  defp normalize_evidence(observations) when is_map(observations), do: %{@observations_key => observations}
  defp normalize_evidence(_evidence), do: %{@observations_key => %{}}

  defp tracker_issue_observations(issue) do
    case issue_change_proposal_attachment(issue) do
      nil ->
        %{}

      attachment ->
        %{
          @change_proposal_key =>
            compact(%{
              @status_key => @linked_status,
              @source_key => @tracker_observed_source,
              @id_key => Map.get(attachment, "id"),
              @url_key => Map.get(attachment, "url"),
              @linked_to_tracker_key => true
            })
        }
    end
  end

  defp issue_change_proposal_attachment(issue) do
    issue
    |> nodes("attachments")
    |> Enum.find(&change_proposal_attachment?/1)
  end

  defp change_proposal_attachment?(attachment) when is_map(attachment) do
    attachment
    |> string_value("url")
    |> change_proposal_url?()
  end

  defp change_proposal_attachment?(_attachment), do: false

  defp change_proposal_url?(url) when is_binary(url) do
    absolute_http_url?(url) and Enum.any?(@change_proposal_path_markers, &String.contains?(url, &1))
  end

  defp change_proposal_url?(_url), do: false

  defp absolute_http_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> true
      _uri -> false
    end
  end

  defp observation(observations, key) when is_map(observations), do: Map.get(observations, key, %{})

  defp trusted_workpad_record?(workpad) when is_map(workpad) do
    Map.get(workpad, @source_key) in [@typed_tool_observed_source, @tracker_observed_source] and
      Map.get(workpad, @status_key) in @passing_workpad_statuses and
      not is_nil(workpad_recorded_at(workpad)) and
      (present?(Map.get(workpad, @workpad_id_key)) or
         present?(Map.get(workpad, @url_key)))
  end

  defp stale_workpad_record?(workpad, readiness_observations) do
    recorded_at = workpad_recorded_at(workpad)
    latest_evidence_at = latest_observed_at(readiness_observations)

    case {recorded_at, latest_evidence_at} do
      {%DateTime{} = recorded, %DateTime{} = latest} -> DateTime.compare(recorded, latest) == :lt
      _timestamps -> false
    end
  end

  defp workpad_recorded_at(workpad) when is_map(workpad) do
    workpad
    |> Map.get(@updated_at_key)
    |> parse_datetime()
    |> case do
      %DateTime{} = updated_at -> updated_at
      nil -> parsed_observed_at(workpad)
    end
  end

  defp code_change_observed?(repo) do
    present?(Map.get(repo, @head_sha_key)) or
      present?(Map.get(repo, @published_head_sha_key)) or
      List.wrap(Map.get(repo, @commits_key)) != []
  end

  defp current_head(repo, change_proposal) do
    Map.get(repo || %{}, @published_head_sha_key) ||
      Map.get(repo || %{}, @head_sha_key) ||
      Map.get(change_proposal || %{}, @head_sha_key)
  end

  defp stale_observation?(observation, repo, change_proposal) do
    observed_at = parsed_observed_at(observation)
    latest_head_observed_at = latest_observed_at([repo, change_proposal])

    case {observed_at, latest_head_observed_at} do
      {%DateTime{} = observed, %DateTime{} = latest} -> DateTime.compare(observed, latest) == :lt
      _timestamps -> false
    end
  end

  defp latest_observed_at(values) do
    values
    |> Enum.flat_map(fn value ->
      case parsed_observed_at(value) do
        %DateTime{} = observed_at -> [observed_at]
        nil -> []
      end
    end)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  defp parsed_observed_at(value) when is_map(value) do
    value
    |> Map.get(@observed_at_key)
    |> parse_datetime()
  end

  defp parsed_observed_at(_value), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp latest_command_head(validation) when is_map(validation) do
    validation
    |> Map.get(@commands_key, [])
    |> List.wrap()
    |> Enum.find_value(&Map.get(&1, @head_sha_key))
  end

  defp latest_command_head(_validation), do: nil

  defp stale_head?(left, right), do: present?(left) and present?(right) and left != right

  defp change_proposal_required?(workflow) do
    workflow
    |> profile_options()
    |> CodingPrDelivery.change_proposal_required?()
  end

  defp change_proposal_checks_not_required?(workflow) do
    workflow
    |> profile_options()
    |> CodingPrDelivery.review_handoff_change_proposal_checks_not_required?()
  end

  defp observed(value, prefix) when is_map(value) and map_size(value) > 0 do
    [
      if(present?(Map.get(value, @source_key)), do: "#{prefix}.#{@source_key}=#{Map.get(value, @source_key)}"),
      if(present?(Map.get(value, @status_key)), do: "#{prefix}.#{@status_key}=#{Map.get(value, @status_key)}"),
      if(present?(Map.get(value, @head_sha_key)), do: "#{prefix}.#{@head_sha_key}"),
      if(present?(Map.get(value, @url_key)), do: "#{prefix}.#{@url_key}"),
      if(Map.get(value, @linked_to_tracker_key) == true, do: "#{prefix}.#{@linked_to_tracker_key}")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp observed(_value, _prefix), do: []

  defp issue_keys(issue, explicit_key) do
    [
      explicit_key,
      string_value(issue, "id"),
      string_value(issue, "identifier")
    ]
    |> Enum.flat_map(&present_values/1)
    |> Enum.uniq()
  end

  defp nodes(map, key) when is_map(map) do
    case Map.get(map, key) || map_get_existing_atom(map, key) do
      %{"nodes" => nodes} when is_list(nodes) -> nodes
      %{nodes: nodes} when is_list(nodes) -> nodes
      nodes when is_list(nodes) -> nodes
      _value -> []
    end
  end

  defp route_key_for_state(workflow, state_name) when is_binary(state_name) do
    RoutePolicy.route_key_for_raw_state(state_name, raw_state_by_route_key(workflow), CodingPrDelivery)
  end

  defp route_key_for_state(_workflow, _state_name), do: nil

  defp lifecycle_phase_for_state(workflow, state_name) when is_binary(state_name) do
    WorkflowLifecycle.phase_for_state(state_name, state_phase_map(workflow))
  end

  defp lifecycle_phase_for_state(_workflow, _state_name), do: nil

  defp logical_review_target?(target_state_name) when is_binary(target_state_name) do
    RoutePolicy.normalize_route_key(target_state_name, CodingPrDelivery) == CodingPrDelivery.review_route_key() or
      WorkflowLifecycle.human_review_phase?(target_state_name)
  end

  defp logical_review_target?(_target_state_name), do: false

  defp profile_kind(%Effective{profile_kind: profile_kind}), do: profile_kind
  defp profile_kind(%{profile_kind: profile_kind}) when is_binary(profile_kind), do: profile_kind
  defp profile_kind(%{"profile_kind" => profile_kind}) when is_binary(profile_kind), do: profile_kind
  defp profile_kind(%{profile: %{kind: kind}}) when is_binary(kind), do: kind
  defp profile_kind(%{"profile" => %{"kind" => kind}}) when is_binary(kind), do: kind
  defp profile_kind(_workflow), do: nil

  defp profile_version(%Effective{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{profile_version: version}) when is_integer(version), do: version
  defp profile_version(%{"profile_version" => version}) when is_integer(version), do: version
  defp profile_version(%{profile: %{version: version}}) when is_integer(version), do: version
  defp profile_version(%{"profile" => %{"version" => version}}) when is_integer(version), do: version
  defp profile_version(workflow), do: if(profile_kind(workflow) == CodingPrDelivery.kind(), do: CodingPrDelivery.version())

  defp workflow_profile_ref(workflow) do
    %{
      kind: profile_kind(workflow),
      version: profile_version(workflow)
    }
  end

  defp profile_options(%Effective{profile_options: options}) when is_map(options), do: options
  defp profile_options(%{profile_options: options}) when is_map(options), do: options
  defp profile_options(%{"profile_options" => options}) when is_map(options), do: options
  defp profile_options(%{"profileOptions" => options}) when is_map(options), do: options
  defp profile_options(_workflow), do: %{}

  defp raw_state_by_route_key(%Effective{raw_state_by_route_key: map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{raw_state_by_route_key: map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{"raw_state_by_route_key" => map}) when is_map(map), do: map
  defp raw_state_by_route_key(%{"rawStateByRouteKey" => map}) when is_map(map), do: map
  defp raw_state_by_route_key(_workflow), do: %{}

  defp state_phase_map(%Effective{state_phase_map: map}) when is_map(map), do: map
  defp state_phase_map(%{state_phase_map: map}) when is_map(map), do: map
  defp state_phase_map(%{"state_phase_map" => map}) when is_map(map), do: map
  defp state_phase_map(%{"statePhaseMap" => map}) when is_map(map), do: map
  defp state_phase_map(_workflow), do: %{}

  defp string_value(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) || map_get_existing_atom(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      value when is_atom(value) ->
        value |> Atom.to_string() |> String.trim()

      _value ->
        nil
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
  defp present_values(value) when is_atom(value), do: present_values(Atom.to_string(value))
  defp present_values(_value), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp integer(_value, default), do: default

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
