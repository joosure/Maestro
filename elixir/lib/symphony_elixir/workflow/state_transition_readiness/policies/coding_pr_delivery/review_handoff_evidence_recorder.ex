defmodule SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffEvidenceRecorder do
  @moduledoc """
  Normalizes successful typed-tool results into coding PR delivery review-handoff evidence.
  """

  alias SymphonyElixir.Workflow.StateTransitionReadiness.Contract, as: StateTransitionReadinessContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.EvidenceRecorder.Behaviour, as: EvidenceRecorderBehaviour
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Policies.CodingPrDelivery.ReviewHandoffToolContract
  alias SymphonyElixir.Workflow.StateTransitionReadiness.Store

  @behaviour EvidenceRecorderBehaviour

  @observations_key StateTransitionReadinessContract.observations_key()
  @workpad_key StateTransitionReadinessContract.workpad_key()
  @repo_key StateTransitionReadinessContract.repo_key()
  @change_proposal_key StateTransitionReadinessContract.change_proposal_key()
  @validation_key StateTransitionReadinessContract.validation_key()
  @checks_key StateTransitionReadinessContract.checks_key()
  @feedback_key StateTransitionReadinessContract.feedback_key()

  @status_key StateTransitionReadinessContract.status_key()
  @source_key StateTransitionReadinessContract.source_key()
  @id_key StateTransitionReadinessContract.id_key()
  @url_key StateTransitionReadinessContract.url_key()
  @head_ref_key StateTransitionReadinessContract.head_ref_key()
  @head_sha_key StateTransitionReadinessContract.head_sha_key()
  @published_head_sha_key StateTransitionReadinessContract.published_head_sha_key()
  @commits_key StateTransitionReadinessContract.commits_key()
  @change_kind_key StateTransitionReadinessContract.change_kind_key()
  @linked_to_tracker_key StateTransitionReadinessContract.linked_to_tracker_key()
  @observed_at_key StateTransitionReadinessContract.observed_at_key()
  @commands_key StateTransitionReadinessContract.commands_key()
  @comment_id_key StateTransitionReadinessContract.comment_id_key()
  @updated_at_key StateTransitionReadinessContract.updated_at_key()
  @provider_kind_key StateTransitionReadinessContract.provider_kind_key()
  @repository_key StateTransitionReadinessContract.repository_key()
  @number_key StateTransitionReadinessContract.number_key()
  @summary_key StateTransitionReadinessContract.summary_key()
  @actionable_count_key StateTransitionReadinessContract.actionable_count_key()
  @working_tree_clean_key StateTransitionReadinessContract.working_tree_clean_key()
  @pushed_key StateTransitionReadinessContract.pushed_key()
  @command_key StateTransitionReadinessContract.command_key()
  @cwd_key StateTransitionReadinessContract.cwd_key()
  @exit_code_key StateTransitionReadinessContract.exit_code_key()

  @passed_status StateTransitionReadinessContract.passed_status()
  @failed_status StateTransitionReadinessContract.failed_status()
  @unknown_status StateTransitionReadinessContract.unknown_status()
  @not_required_status StateTransitionReadinessContract.not_required_status()
  @pending_status StateTransitionReadinessContract.pending_status()
  @linked_status StateTransitionReadinessContract.linked_status()
  @created_status StateTransitionReadinessContract.created_status()
  @updated_status StateTransitionReadinessContract.updated_status()
  @missing_status StateTransitionReadinessContract.missing_status()
  @clear_status StateTransitionReadinessContract.clear_status()
  @action_required_status StateTransitionReadinessContract.action_required_status()

  @code_change_kind StateTransitionReadinessContract.code_change_kind()
  @typed_tool_observed_source StateTransitionReadinessContract.typed_tool_observed_source()
  @tracker_observed_source StateTransitionReadinessContract.tracker_observed_source()
  @repo_observed_source StateTransitionReadinessContract.repo_observed_source()
  @repo_provider_observed_source StateTransitionReadinessContract.repo_provider_observed_source()

  @passed_check_buckets [@passed_status, "success", "successful", "green", "neutral", "skipped"]
  @failed_check_buckets [@failed_status, "failure", "error", "cancelled", "canceled", "timed_out", "timedout", "red"]
  @pending_check_buckets [@pending_status, "queued", "running", "in_progress", "waiting", "yellow"]

  @spec record_typed_tool_result(String.t() | atom() | nil, term(), String.t() | nil, term(), term(), keyword()) :: :ok
  @impl EvidenceRecorderBehaviour
  def record_typed_tool_result(source_kind, source_context, tool, arguments, result, opts \\ [])

  def record_typed_tool_result(source_kind, source_context, tool, arguments, {:success, payload}, opts)
      when is_binary(tool) and is_list(opts) do
    observations = observations(source_kind, source_context, tool, arguments, payload, opts)
    keys = issue_keys(arguments, opts)

    if map_size(observations) > 0 do
      Store.record(keys, %{@observations_key => observations})
    else
      :ok
    end
  end

  def record_typed_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok

  defp observations(_source_kind, _source_context, tool, arguments, payload, _opts) do
    case ReviewHandoffToolContract.evidence_kind(tool) do
      :workpad -> workpad_observation(arguments, payload)
      :tracker_change_proposal -> tracker_change_proposal_observation(arguments, payload)
      :repo_commit -> repo_commit_observation(payload)
      :repo_push -> repo_push_observation(payload)
      :repo_diff_validation -> repo_diff_validation_observation(arguments, payload)
      :repo_provider_change_proposal -> repo_provider_change_proposal_observation(payload)
      :repo_provider_checks -> repo_provider_checks_observation(payload)
      :repo_provider_feedback -> repo_provider_feedback_observation(payload)
      :repo_provider_snapshot -> repo_provider_snapshot_observation(payload)
      nil -> %{}
    end
  end

  defp workpad_observation(_arguments, payload) do
    comment = get_in(payload, ["data", "comment"]) || %{}

    %{
      @workpad_key =>
        compact(%{
          @status_key => workpad_write_status(comment),
          @source_key => @typed_tool_observed_source,
          @comment_id_key => string_value(comment, "id"),
          @updated_at_key => generated_at()
        })
    }
  end

  defp tracker_change_proposal_observation(arguments, payload) do
    attachment = get_in(payload, ["data", "attachment"]) || %{}
    url = string_value(attachment, "url") || string_value(arguments, "url")

    %{
      @change_proposal_key =>
        compact(%{
          @status_key => @linked_status,
          @source_key => @tracker_observed_source,
          @url_key => url,
          @id_key => string_value(arguments, "change_proposal_id") || string_value(attachment, "id"),
          @provider_kind_key => string_value(arguments, "repo_provider_kind"),
          @repository_key => string_value(arguments, "repository"),
          @linked_to_tracker_key => true,
          @observed_at_key => generated_at()
        })
    }
  end

  defp repo_commit_observation(payload) do
    data = Map.get(payload, "data", %{})
    status = Map.get(data, "status", %{})
    head_sha = string_value(data, "headSha") || string_value(status, "headSha")
    action = string_value(data, "action")

    repo =
      %{
        @source_key => @repo_observed_source,
        @change_kind_key => if(action == "committed" and present?(head_sha), do: @code_change_kind, else: @unknown_status),
        @head_ref_key => string_value(status, "branch"),
        @head_sha_key => head_sha,
        @commits_key => if(present?(head_sha), do: [%{"sha" => head_sha}], else: []),
        @working_tree_clean_key => Map.get(status, "clean"),
        @observed_at_key => generated_at()
      }
      |> compact()

    %{@repo_key => repo}
  end

  defp repo_push_observation(payload) do
    data = Map.get(payload, "data", %{})
    head_sha = string_value(data, "headSha") || string_value(data, "publishedHeadSha")

    %{
      @repo_key =>
        compact(%{
          @source_key => @repo_observed_source,
          @change_kind_key => if(present?(head_sha), do: @code_change_kind, else: @unknown_status),
          @head_ref_key => string_value(data, "branch"),
          @head_sha_key => head_sha,
          @published_head_sha_key => string_value(data, "publishedHeadSha"),
          @pushed_key => present?(string_value(data, "publishedHeadSha")),
          @observed_at_key => generated_at()
        })
    }
  end

  defp repo_diff_validation_observation(arguments, payload) do
    data = Map.get(payload, "data", %{})

    if Map.has_key?(data, "diffCheck") and not is_nil(Map.get(data, "diffCheck")) do
      status = Map.get(data, "status", %{})
      args = arguments |> value("args") |> string_list()

      %{
        @validation_key =>
          compact(%{
            @status_key => @passed_status,
            @source_key => @typed_tool_observed_source,
            @commands_key => [
              compact(%{
                @id_key => "repo_diff_check",
                @command_key => Enum.join(["git", "diff", "--check" | args], " "),
                @cwd_key => string_value(status, "root") || string_value(status, "path"),
                @exit_code_key => 0,
                @head_sha_key => string_value(status, "headSha"),
                @source_key => @typed_tool_observed_source
              })
            ],
            @head_sha_key => string_value(status, "headSha"),
            @observed_at_key => generated_at()
          })
      }
    else
      %{}
    end
  end

  defp repo_provider_change_proposal_observation(payload) do
    data = Map.get(payload, "data", %{})
    proposal = Map.get(data, "changeProposal", %{}) || %{}
    action = string_value(data, "action")

    cond do
      Map.get(data, "exists") == false ->
        %{
          @change_proposal_key =>
            compact(%{
              @status_key => @missing_status,
              @source_key => @repo_provider_observed_source,
              @observed_at_key => generated_at()
            })
        }

      not is_map(proposal) or map_size(proposal) == 0 ->
        %{}

      true ->
        status =
          case action do
            "created" -> @created_status
            "updated" -> @updated_status
            _action -> @updated_status
          end

        %{
          @change_proposal_key =>
            compact(%{
              @status_key => status,
              @source_key => @repo_provider_observed_source,
              @provider_kind_key => string_value(proposal, "provider"),
              @repository_key => string_value(proposal, "repository"),
              @id_key => string_value(proposal, "id"),
              @number_key => string_value(proposal, "number"),
              @url_key => string_value(proposal, "url"),
              @head_ref_key => string_value(proposal, "headRefName") || string_value(proposal, "head_ref") || string_value(proposal, "branch"),
              @head_sha_key => string_value(proposal, "headRefOid") || string_value(proposal, "headSha") || string_value(proposal, "head_sha"),
              @observed_at_key => generated_at()
            })
        }
    end
  end

  defp repo_provider_checks_observation(payload) do
    payload
    |> get_in(["data", "checks"])
    |> checks_observation()
  end

  defp repo_provider_feedback_observation(payload) do
    payload
    |> get_in(["data", "discussion"])
    |> feedback_observation()
  end

  defp repo_provider_snapshot_observation(payload) do
    data = Map.get(payload, "data", %{})

    %{}
    |> deep_merge(repo_provider_change_proposal_observation(%{"data" => data}))
    |> deep_merge(checks_observation(Map.get(data, "checks")))
    |> deep_merge(feedback_observation(Map.get(data, "discussion")))
  end

  defp checks_observation(checks) when is_map(checks) do
    status = checks_status(checks)

    head_sha =
      if status == @not_required_status do
        nil
      else
        string_value(checks, "headSha") || string_value(checks, "head_sha")
      end

    %{
      @checks_key =>
        compact(%{
          @status_key => status,
          @source_key => @repo_provider_observed_source,
          @summary_key => Map.get(checks, "summary"),
          @head_sha_key => head_sha,
          @observed_at_key => generated_at()
        })
    }
  end

  defp checks_observation(_checks), do: %{}

  defp feedback_observation(discussion) when is_map(discussion) do
    summary = Map.get(discussion, "summary", %{}) || %{}
    actionable_count = integer_value(summary, "actionableFeedbackCount") || length(List.wrap(Map.get(discussion, "actionableItems")))

    %{
      @feedback_key =>
        compact(%{
          @status_key => if(actionable_count > 0, do: @action_required_status, else: @clear_status),
          @source_key => @repo_provider_observed_source,
          @actionable_count_key => actionable_count,
          @observed_at_key => generated_at()
        })
    }
  end

  defp feedback_observation(_discussion), do: %{}

  defp workpad_write_status(%{"created" => true}), do: @created_status
  defp workpad_write_status(%{"updated" => true}), do: @updated_status
  defp workpad_write_status(_comment), do: @updated_status

  defp checks_status(%{"runs" => runs}) when is_list(runs) do
    cond do
      runs == [] -> @not_required_status
      Enum.any?(runs, &(check_bucket(&1) in @failed_check_buckets)) -> @failed_status
      Enum.any?(runs, &(check_bucket(&1) in @pending_check_buckets)) -> @pending_status
      Enum.all?(runs, &(check_bucket(&1) in @passed_check_buckets)) -> @passed_status
      true -> @unknown_status
    end
  end

  defp checks_status(%{"summary" => summary}) when is_map(summary), do: checks_summary_status(summary)
  defp checks_status(_checks), do: @unknown_status

  defp checks_summary_status(summary) when is_map(summary) do
    cond do
      summary == %{} -> @not_required_status
      Enum.any?(@failed_check_buckets, fn bucket -> (integer_value(summary, bucket) || 0) > 0 end) -> @failed_status
      Enum.any?(@pending_check_buckets, fn bucket -> (integer_value(summary, bucket) || 0) > 0 end) -> @pending_status
      Enum.any?(@passed_check_buckets, fn bucket -> (integer_value(summary, bucket) || 0) > 0 end) -> @passed_status
      true -> @unknown_status
    end
  end

  defp check_bucket(check) when is_map(check) do
    (string_value(check, "bucket") || string_value(check, "state") || @unknown_status)
    |> String.downcase()
  end

  defp check_bucket(_check), do: @unknown_status

  defp issue_keys(arguments, opts) do
    runtime_metadata = opts |> Keyword.get(:tool_context) |> runtime_metadata()
    run_id = Keyword.get(opts, :run_id) || Map.get(runtime_metadata, :run_id) || Map.get(runtime_metadata, "run_id")

    issue_keys =
      [
        value(arguments, "issue_id"),
        value(arguments, "issue_identifier"),
        Keyword.get(opts, :issue_id),
        Keyword.get(opts, :issue_identifier),
        Map.get(runtime_metadata, :issue_id),
        Map.get(runtime_metadata, "issue_id"),
        Map.get(runtime_metadata, :issue_identifier),
        Map.get(runtime_metadata, "issue_identifier")
      ]
      |> Enum.flat_map(&present_values/1)
      |> Enum.uniq()

    Store.scope_issue_keys(run_id, issue_keys)
  end

  defp runtime_metadata(%{runtime_metadata: metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(%{"runtime_metadata" => metadata}) when is_map(metadata), do: metadata
  defp runtime_metadata(_context), do: %{}

  defp present_values(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp present_values(value) when is_integer(value), do: [Integer.to_string(value)]
  defp present_values(value) when is_atom(value), do: present_values(Atom.to_string(value))
  defp present_values(_value), do: []

  defp string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&present_values/1)
    |> Enum.map(&String.trim/1)
  end

  defp string_list(_values), do: []

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || map_get_existing_atom(map, key)
  end

  defp value(_map, _key), do: nil

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      value when is_atom(value) ->
        value |> Atom.to_string() |> string_value_from_string()

      _value ->
        nil
    end
  end

  defp string_value_from_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

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

  defp map_get_existing_atom(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp compact(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value), do: deep_merge(left_value, right_value), else: right_value
    end)
  end

  defp generated_at, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
