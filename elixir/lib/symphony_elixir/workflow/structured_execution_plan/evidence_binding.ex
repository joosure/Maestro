defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.EvidenceBinding do
  @moduledoc """
  Normalizes successful typed workflow tool results into structured plan evidence refs.

  This module only builds bounded provider-neutral evidence. It does not expose
  provider tools and does not decide readiness policy.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract, as: StateTransitionReadinessContract

  @repo_commit_tool "repo_commit"
  @repo_push_tool "repo_push"
  @repo_diff_tool "repo_diff"
  @repo_create_or_update_change_proposal_tool "repo_create_or_update_change_proposal"
  @repo_change_proposal_snapshot_tool "repo_change_proposal_snapshot"
  @repo_read_change_proposal_checks_tool "repo_read_change_proposal_checks"
  @repo_read_change_proposal_discussion_tool "repo_read_change_proposal_discussion"

  @linear_attach_change_proposal_tool "linear_attach_change_proposal"
  @tapd_attach_change_proposal_tool "tapd_attach_change_proposal"
  @linear_upsert_workpad_tool "linear_upsert_workpad"
  @tapd_upsert_workpad_tool "tapd_upsert_workpad"
  @linear_move_issue_tool "linear_move_issue"
  @tapd_move_issue_tool "tapd_move_issue"
  @passed_status StateTransitionReadinessContract.passed_status()
  @failed_status StateTransitionReadinessContract.failed_status()
  @pending_status StateTransitionReadinessContract.pending_status()
  @unknown_status StateTransitionReadinessContract.unknown_status()
  @unavailable_status StateTransitionReadinessContract.unavailable_status()
  @failed_check_buckets [@failed_status, "failure", "error", "cancelled", "canceled", "timed_out", "timedout", "red"]
  @pending_check_buckets [@pending_status, "queued", "running", "in_progress", "waiting", "yellow"]
  @passed_check_buckets [@passed_status, "success", "successful", "green", "neutral", "skipped"]

  @type bind_result :: {:ok, [map()]} | {:error, map()}

  @spec bind_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) ::
          bind_result()
  def bind_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ [])

  def bind_typed_tool_result(source_kind, source_context, tool, arguments, {:success, payload}, opts)
      when is_binary(tool) and is_list(opts) do
    case evidence_kind(tool) do
      nil ->
        {:ok, []}

      evidence_kind ->
        with {:ok, scope} <- evidence_scope(arguments, opts),
             {:ok, evidence_payload} <- evidence_payload(evidence_kind, source_kind, source_context, arguments, payload) do
          {:ok, [evidence_ref(evidence_kind, tool, scope, evidence_payload, opts)]}
        end
    end
  end

  def bind_typed_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: {:ok, []}

  @spec evidence_kind(String.t() | nil) :: String.t() | nil
  def evidence_kind(@repo_commit_tool), do: "repo_commit"
  def evidence_kind(@repo_push_tool), do: "repo_push"
  def evidence_kind(@repo_diff_tool), do: "repo_diff"
  def evidence_kind(@repo_create_or_update_change_proposal_tool), do: "repo_create_or_update_change_proposal"
  def evidence_kind(@repo_change_proposal_snapshot_tool), do: "repo_change_proposal_snapshot"
  def evidence_kind(@repo_read_change_proposal_checks_tool), do: "repo_read_change_proposal_checks"
  def evidence_kind(@repo_read_change_proposal_discussion_tool), do: "repo_read_change_proposal_discussion"
  def evidence_kind(@linear_attach_change_proposal_tool), do: "tracker_attach_change_proposal"
  def evidence_kind(@tapd_attach_change_proposal_tool), do: "tracker_attach_change_proposal"
  def evidence_kind(@linear_upsert_workpad_tool), do: "tracker_upsert_workpad"
  def evidence_kind(@tapd_upsert_workpad_tool), do: "tracker_upsert_workpad"
  def evidence_kind(@linear_move_issue_tool), do: "tracker_move_issue"
  def evidence_kind(@tapd_move_issue_tool), do: "tracker_move_issue"
  def evidence_kind(_tool), do: nil

  @spec idempotency_key(map()) :: String.t()
  def idempotency_key(%{"evidence_kind" => evidence_kind, "producer" => producer, "run_id" => run_id, "issue_id" => issue_id, "payload" => payload}) do
    idempotency_key(evidence_kind, producer, %{run_id: run_id, issue_id: issue_id}, payload)
  end

  defp evidence_ref(evidence_kind, producer, scope, payload, opts) do
    %{
      "evidence_id" => evidence_id(evidence_kind, producer, scope, payload),
      "evidence_kind" => evidence_kind,
      "source" => "tool_generated",
      "producer" => producer,
      "run_id" => Map.fetch!(scope, :run_id),
      "issue_id" => Map.fetch!(scope, :issue_id),
      "observed_at" => observed_at(opts),
      "payload" => payload
    }
  end

  defp evidence_scope(arguments, opts) do
    runtime_metadata = opts |> Keyword.get(:tool_context) |> runtime_metadata()

    scope = %{
      run_id: first_present([Keyword.get(opts, :run_id), value(arguments, "run_id"), map_value(runtime_metadata, :run_id)]),
      issue_id:
        first_present([
          value(arguments, "issue_id"),
          Keyword.get(opts, :issue_id),
          map_value(runtime_metadata, :issue_id),
          value(arguments, "issue_identifier"),
          Keyword.get(opts, :issue_identifier),
          map_value(runtime_metadata, :issue_identifier)
        ])
    }

    cond do
      is_nil(scope.run_id) ->
        {:error, %{code: "missing_run_id", message: "Structured plan evidence requires a run_id."}}

      is_nil(scope.issue_id) ->
        {:error, %{code: "missing_issue_id", message: "Structured plan evidence requires an issue_id."}}

      true ->
        {:ok, scope}
    end
  end

  defp evidence_payload("repo_commit", _source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})
    status = Map.get(data, "status", %{})

    {:ok,
     compact(%{
       "head_sha" => string_value(data, "headSha") || string_value(status, "headSha"),
       "branch" => string_value(status, "branch"),
       "working_tree_clean" => Map.get(status, "clean"),
       "action" => string_value(data, "action"),
       "repository" => repo_repository(source_context)
     })}
  end

  defp evidence_payload("repo_push", _source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})

    {:ok,
     compact(%{
       "branch" => string_value(data, "branch"),
       "remote" => string_value(data, "remote"),
       "head_sha" => string_value(data, "headSha"),
       "published_head_sha" => string_value(data, "publishedHeadSha"),
       "repository" => repo_repository(source_context)
     })}
  end

  defp evidence_payload("repo_diff", _source_kind, _source_context, arguments, payload) do
    data = Map.get(payload, "data", %{})
    status = Map.get(data, "status", %{})

    {:ok,
     compact(%{
       "check" => Map.has_key?(data, "diffCheck") and not is_nil(Map.get(data, "diffCheck")),
       "head_sha" => string_value(status, "headSha"),
       "cwd" => string_value(status, "root") || string_value(status, "path"),
       "args" => string_list(value(arguments, "args"))
     })}
  end

  defp evidence_payload("repo_create_or_update_change_proposal", source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})
    proposal = Map.get(data, "changeProposal", %{}) || %{}

    {:ok,
     proposal_payload(proposal)
     |> Map.put("action", string_value(data, "action"))
     |> Map.put("provider_kind", provider_kind(source_kind, source_context))
     |> compact()}
  end

  defp evidence_payload("repo_change_proposal_snapshot", source_kind, source_context, _arguments, payload) do
    data = Map.get(payload, "data", %{})
    proposal = Map.get(data, "changeProposal", %{}) || %{}

    snapshot =
      proposal_payload(proposal)
      |> Map.put("exists", Map.get(data, "exists"))
      |> Map.put("provider_kind", provider_kind(source_kind, source_context))
      |> put_checks_summary(Map.get(data, "checks"))
      |> put_discussion_summary(Map.get(data, "discussion"))
      |> compact()

    {:ok, snapshot}
  end

  defp evidence_payload("repo_read_change_proposal_checks", _source_kind, _source_context, _arguments, payload) do
    checks = get_in(payload, ["data", "checks"]) || %{}

    {:ok,
     compact(%{
       "status" => checks_status(checks),
       "head_sha" => string_value(checks, "headSha") || string_value(checks, "head_sha"),
       "summary" => Map.get(checks, "summary"),
       "run_count" => checks |> Map.get("runs") |> list_length()
     })}
  end

  defp evidence_payload("repo_read_change_proposal_discussion", _source_kind, _source_context, _arguments, payload) do
    discussion = get_in(payload, ["data", "discussion"]) || %{}
    summary = Map.get(discussion, "summary", %{}) || %{}
    actionable_count = integer_value(summary, "actionableFeedbackCount") || discussion |> Map.get("actionableItems") |> list_length()

    {:ok,
     compact(%{
       "status" => if(actionable_count > 0, do: "action_required", else: "clear"),
       "actionable_count" => actionable_count
     })}
  end

  defp evidence_payload("tracker_attach_change_proposal", source_kind, _source_context, arguments, payload) do
    attachment = get_in(payload, ["data", "attachment"]) || %{}

    {:ok,
     compact(%{
       "tracker_kind" => source_kind && to_string(source_kind),
       "attachment_id" => string_value(attachment, "id"),
       "url" => string_value(attachment, "url") || string_value(arguments, "url"),
       "change_proposal_id" => string_value(arguments, "change_proposal_id") || string_value(attachment, "id"),
       "repo_provider_kind" => string_value(arguments, "repo_provider_kind"),
       "repository" => string_value(arguments, "repository"),
       "linked_to_tracker" => true
     })}
  end

  defp evidence_payload("tracker_upsert_workpad", source_kind, _source_context, _arguments, payload) do
    comment = get_in(payload, ["data", "comment"]) || %{}

    {:ok,
     compact(%{
       "tracker_kind" => source_kind && to_string(source_kind),
       "workpad_id" => string_value(comment, "id"),
       "created" => Map.get(comment, "created"),
       "updated" => Map.get(comment, "updated")
     })}
  end

  defp evidence_payload("tracker_move_issue", source_kind, _source_context, arguments, payload) do
    issue = get_in(payload, ["data", "issue"]) || %{}
    state = Map.get(issue, "state", %{}) || %{}

    {:ok,
     compact(%{
       "tracker_kind" => source_kind && to_string(source_kind),
       "issue_id" => string_value(issue, "id") || string_value(arguments, "issue_id"),
       "state_name" => string_value(state, "name") || string_value(arguments, "state_name"),
       "state_id" => string_value(state, "id"),
       "route_key" => string_value(arguments, "route_key"),
       "lifecycle_phase" => string_value(arguments, "lifecycle_phase")
     })}
  end

  defp evidence_payload(_evidence_kind, _source_kind, _source_context, _arguments, _payload), do: {:ok, %{}}

  defp evidence_id(evidence_kind, producer, scope, payload) do
    "evidence_" <> String.slice(idempotency_key(evidence_kind, producer, scope, payload), 0, 22)
  end

  defp idempotency_key(evidence_kind, producer, scope, payload) do
    identity =
      payload
      |> Map.take(identity_fields(evidence_kind))
      |> Map.put("evidence_kind", evidence_kind)
      |> Map.put("producer", producer)
      |> Map.put("run_id", Map.fetch!(scope, :run_id))
      |> Map.put("issue_id", Map.fetch!(scope, :issue_id))

    identity
    |> :erlang.term_to_binary()
    |> short_hash()
  end

  defp identity_fields("repo_commit"), do: ["head_sha"]
  defp identity_fields("repo_push"), do: ["branch", "head_sha", "published_head_sha"]
  defp identity_fields("repo_diff"), do: ["check", "head_sha", "args"]
  defp identity_fields("repo_create_or_update_change_proposal"), do: ["provider_kind", "repository", "number", "url", "head_ref", "head_sha", "action"]
  defp identity_fields("repo_change_proposal_snapshot"), do: ["provider_kind", "repository", "number", "url", "head_ref", "head_sha", "exists"]
  defp identity_fields("repo_read_change_proposal_checks"), do: ["status", "head_sha", "run_count"]
  defp identity_fields("repo_read_change_proposal_discussion"), do: ["status", "actionable_count"]
  defp identity_fields("tracker_attach_change_proposal"), do: ["tracker_kind", "attachment_id", "url"]
  defp identity_fields("tracker_upsert_workpad"), do: ["tracker_kind", "workpad_id"]
  defp identity_fields("tracker_move_issue"), do: ["tracker_kind", "issue_id", "state_name", "state_id"]
  defp identity_fields(_evidence_kind), do: []

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      value when is_binary(value) -> value
      _value -> DateTime.utc_now() |> DateTime.to_iso8601()
    end
  end

  defp proposal_payload(proposal) when is_map(proposal) and map_size(proposal) > 0 do
    compact(%{
      "provider_kind" => string_value(proposal, "provider"),
      "repository" => string_value(proposal, "repository"),
      "id" => string_value(proposal, "id"),
      "number" => string_value(proposal, "number") || string_value(proposal, "target"),
      "url" => string_value(proposal, "url"),
      "head_ref" => string_value(proposal, "headRefName") || string_value(proposal, "head_ref") || string_value(proposal, "branch"),
      "head_sha" => string_value(proposal, "headRefOid") || string_value(proposal, "headSha") || string_value(proposal, "head_sha")
    })
  end

  defp proposal_payload(_proposal), do: %{}

  defp put_checks_summary(payload, checks) when is_map(checks) do
    payload
    |> Map.put("checks_status", checks_status(checks))
    |> Map.put("checks_head_sha", string_value(checks, "headSha") || string_value(checks, "head_sha"))
  end

  defp put_checks_summary(payload, _checks), do: payload

  defp put_discussion_summary(payload, discussion) when is_map(discussion) do
    summary = Map.get(discussion, "summary", %{}) || %{}
    actionable_count = integer_value(summary, "actionableFeedbackCount") || discussion |> Map.get("actionableItems") |> list_length()

    payload
    |> Map.put("discussion_status", if(actionable_count > 0, do: "action_required", else: "clear"))
    |> Map.put("discussion_actionable_count", actionable_count)
  end

  defp put_discussion_summary(payload, _discussion), do: payload

  defp checks_status(%{"runs" => runs}) when is_list(runs) do
    cond do
      runs == [] -> @unavailable_status
      Enum.any?(runs, &(check_bucket(&1) in @failed_check_buckets)) -> @failed_status
      Enum.any?(runs, &(check_bucket(&1) in @pending_check_buckets)) -> @pending_status
      Enum.all?(runs, &(check_bucket(&1) in @passed_check_buckets)) -> @passed_status
      true -> @unknown_status
    end
  end

  defp checks_status(%{"summary" => summary}) when is_map(summary) do
    cond do
      summary == %{} -> @unavailable_status
      Enum.any?(@failed_check_buckets, fn key -> (integer_value(summary, key) || 0) > 0 end) -> @failed_status
      Enum.any?(@pending_check_buckets, fn key -> (integer_value(summary, key) || 0) > 0 end) -> @pending_status
      Enum.any?(@passed_check_buckets, fn key -> (integer_value(summary, key) || 0) > 0 end) -> @passed_status
      true -> @unknown_status
    end
  end

  defp checks_status(_checks), do: @unknown_status

  defp check_bucket(check) when is_map(check) do
    (string_value(check, "bucket") || string_value(check, "state") || @unknown_status)
    |> String.downcase()
  end

  defp check_bucket(_check), do: @unknown_status

  defp provider_kind(source_kind, source_context) do
    string_value(source_context, "kind") ||
      string_value(source_context, "provider") ||
      string_value(source_context, "provider_kind") ||
      if(source_kind, do: to_string(source_kind))
  end

  defp repo_repository(source_context) do
    string_value(source_context, "repository") || string_value(source_context, "repo")
  end

  defp runtime_metadata(%{runtime_metadata: metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(%{"runtime_metadata" => metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(_context), do: %{}

  defp map_value(map, key) when is_map(map) and is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp map_value(_map, _key), do: nil

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp value(_map, _key), do: nil

  defp string_value(map, key) do
    case value(map, key) do
      nil -> nil
      value when is_binary(value) -> trim_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> trim_string()
      _value -> nil
    end
  end

  defp string_list(values) when is_list(values), do: Enum.flat_map(values, &present_values/1)
  defp string_list(_values), do: []

  defp first_present(values) do
    values
    |> Enum.flat_map(&present_values/1)
    |> List.first()
  end

  defp present_values(nil), do: []

  defp present_values(value) when is_binary(value) do
    case trim_string(value) do
      nil -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: value |> Atom.to_string() |> present_values()
  defp present_values(_value), do: []

  defp integer_value(map, key) when is_map(map) do
    case value(map, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _value -> nil
    end
  end

  defp integer_value(_map, _key), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> nil
    end
  end

  defp list_length(values) when is_list(values), do: length(values)
  defp list_length(_values), do: 0

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp trim_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp short_hash(value) do
    :crypto.hash(:sha256, value)
    |> Base.url_encode64(padding: false)
  end
end
