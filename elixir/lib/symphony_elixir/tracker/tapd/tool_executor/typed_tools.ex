defmodule SymphonyElixir.Tracker.Tapd.ToolExecutor.TypedTools do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.MetadataContract
  alias SymphonyElixir.Issue
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Tapd.Client
  alias SymphonyElixir.Tracker.Tapd.Client.Paths
  alias SymphonyElixir.Tracker.Tapd.Client.Response
  alias SymphonyElixir.Workflow.CapabilityNames

  @source_kind Kinds.tapd()
  @schema_version "1"
  @risk_flags ["external_network", "secret_access", "privileged_api"]
  @metadata_schema_version_key MetadataContract.schema_version()
  @metadata_side_effect_key MetadataContract.side_effect()
  @metadata_risk_flags_key MetadataContract.risk_flags()
  @metadata_workflow_capability_key MetadataContract.workflow_capability()
  @metadata_source_kind_key MetadataContract.source_kind()

  @issue_snapshot_tool "tapd_issue_snapshot"
  @move_issue_tool "tapd_move_issue"
  @upsert_workpad_tool "tapd_upsert_workpad"
  @attach_change_proposal_tool "tapd_attach_change_proposal"
  @upsert_comment_tool "tapd_upsert_comment"
  @create_follow_up_story_tool "tapd_create_follow_up_story"
  @read_story_relations_tool "tapd_read_story_relations"
  @add_story_relation_tool "tapd_add_story_relation"
  @read_story_dependencies_tool "tapd_read_story_dependencies"
  @save_story_dependency_tool "tapd_save_story_dependency"
  @provider_diagnostics_tool "tapd_provider_diagnostics"

  @issue_snapshot_capability CapabilityNames.tracker_issue_snapshot()
  @move_issue_capability CapabilityNames.tracker_move_issue()
  @upsert_workpad_capability CapabilityNames.tracker_upsert_workpad()
  @attach_change_proposal_capability CapabilityNames.tracker_attach_change_proposal()
  @upsert_comment_capability CapabilityNames.tracker_upsert_comment()
  @create_follow_up_issue_capability CapabilityNames.tracker_create_follow_up_issue()
  @read_issue_relations_capability CapabilityNames.tracker_read_issue_relations()
  @add_issue_relation_capability CapabilityNames.tracker_add_issue_relation()
  @read_issue_dependencies_capability CapabilityNames.tracker_read_issue_dependencies()
  @save_issue_dependency_capability CapabilityNames.tracker_save_issue_dependency()
  @provider_diagnostics_capability CapabilityNames.tracker_provider_diagnostics()

  @default_comment_limit 50
  @default_workpad_heading "TAPD Workpad"
  @legacy_workpad_markers ["### Plan", "### Acceptance Criteria", "### Validation", "### Notes"]

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      tool_spec(
        @issue_snapshot_tool,
        @issue_snapshot_capability,
        "Read a TAPD Story snapshot, including raw status, workflow route states, labels, comments, and active workpad candidates.",
        "read_only",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."},
            "include_comments" => %{"type" => "boolean", "description" => "Whether to include Story comments."},
            "include_attachments" => %{"type" => "boolean", "description" => "Reserved for tracker parity; TAPD returns an empty attachment list."},
            "comment_limit" => %{"type" => "integer", "description" => "Maximum comments to read."},
            "workpad_heading" => %{"type" => "string", "description" => "Workpad heading used to identify the active TAPD workpad comment."}
          }
        }
      ),
      tool_spec(
        @move_issue_tool,
        @move_issue_capability,
        "Move a TAPD Story to a workflow route or raw status without exposing raw TAPD request syntax to the agent.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "state_name"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."},
            "state_name" => %{"type" => "string", "description" => "Destination route key, lifecycle phase, or raw TAPD status from the typed snapshot."},
            "expected_current_state" => %{"type" => ["string", "null"], "description" => "Optional optimistic current state, route key, or lifecycle phase check."},
            "reason" => %{"type" => ["string", "null"], "description" => "Optional human-readable reason for the transition."}
          }
        }
      ),
      tool_spec(
        @upsert_workpad_tool,
        @upsert_workpad_capability,
        "Create or update the single TAPD workpad comment. The heading is the stable workpad identity; Markdown is encoded by the TAPD client.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "heading", "body"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."},
            "heading" => %{"type" => "string", "description" => "Workpad title or Markdown heading used as the stable comment identity."},
            "body" => %{"type" => "string", "description" => "Workpad body. The executor prefixes the canonical heading if omitted."},
            "comment_id" => %{"type" => ["string", "null"], "description" => "Existing TAPD comment id to update."},
            "match_heading" => %{"type" => ["string", "null"], "description" => "Optional alternate workpad title or Markdown heading used to find an existing workpad."},
            "mode" => %{"type" => ["string", "null"], "description" => "Upsert mode. The current contract supports replace."},
            "comment_limit" => %{"type" => "integer", "description" => "Maximum comments to scan when matching by heading."}
          }
        }
      ),
      tool_spec(
        @attach_change_proposal_tool,
        @attach_change_proposal_capability,
        "Attach a repository-backed change proposal URL to a TAPD Story through the canonical workpad comment.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "url"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."},
            "url" => %{"type" => "string", "description" => "Absolute change proposal URL."},
            "title" => %{"type" => ["string", "null"], "description" => "Optional attachment title."},
            "workpad_heading" => %{"type" => ["string", "null"], "description" => "Optional workpad heading used for TAPD's comment-backed attachment surface."},
            "repo_provider_kind" => %{"type" => ["string", "null"], "description" => "Optional repo provider kind."},
            "repository" => %{"type" => ["string", "null"], "description" => "Optional provider repository handle."},
            "change_proposal_id" => %{"type" => ["string", "number", "integer", "null"], "description" => "Optional provider change proposal id."}
          }
        }
      ),
      tool_spec(
        @upsert_comment_tool,
        @upsert_comment_capability,
        "Create a TAPD Story comment or update a specific existing comment without exposing raw TAPD REST paths to the agent.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["body"],
          "properties" => %{
            "issue_id" => %{"type" => ["string", "null"], "description" => "Full TAPD Story id or TAPD-<id> identifier. Required when comment_id is omitted."},
            "comment_id" => %{"type" => ["string", "null"], "description" => "Existing TAPD comment id to update."},
            "body" => %{"type" => "string", "description" => "Complete Markdown comment body to create or replace."}
          }
        }
      ),
      tool_spec(
        @create_follow_up_story_tool,
        @create_follow_up_issue_capability,
        "Create a constrained follow-up TAPD Story in the same workspace without exposing raw TAPD Story creation params.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["source_issue_id", "title", "description"],
          "properties" => %{
            "source_issue_id" => %{"type" => "string", "description" => "Current TAPD Story id or TAPD-<id> identifier used as the parent/source."},
            "title" => %{"type" => "string", "description" => "Follow-up Story title."},
            "description" => %{"type" => "string", "description" => "Follow-up Story body with problem statement, scope, and acceptance criteria."},
            "workitem_type_id" => %{"type" => ["string", "null"], "description" => "Optional TAPD workitem type id for the follow-up Story."},
            "priority" => %{"type" => ["string", "null"], "description" => "Optional TAPD priority value."},
            "priority_label" => %{"type" => ["string", "null"], "description" => "Optional TAPD priority label."},
            "label" => %{"type" => ["string", "null"], "description" => "Optional TAPD label string."}
          }
        }
      ),
      tool_spec(
        @read_story_relations_tool,
        @read_issue_relations_capability,
        "Read direct TAPD Story relations for the current Story without raw REST paths.",
        "read_only",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."}
          }
        }
      ),
      tool_spec(
        @add_story_relation_tool,
        @add_issue_relation_capability,
        "Create a direct TAPD Story relation between the current Story and a related Story.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["source_issue_id", "target_issue_id"],
          "properties" => %{
            "source_issue_id" => %{"type" => "string", "description" => "Source TAPD Story id or TAPD-<id> identifier."},
            "target_issue_id" => %{"type" => "string", "description" => "Target TAPD Story id or TAPD-<id> identifier."}
          }
        }
      ),
      tool_spec(
        @read_story_dependencies_tool,
        @read_issue_dependencies_capability,
        "Read TAPD time-relative dependency relations and normalize incoming blockers.",
        "read_only",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Full TAPD Story id or TAPD-<id> identifier."}
          }
        }
      ),
      tool_spec(
        @save_story_dependency_tool,
        @save_issue_dependency_capability,
        "Create or update one TAPD dependency relation using semantic Story ids instead of flattened TAPD form keys.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["blocking_issue_id", "blocked_issue_id", "current_user"],
          "properties" => %{
            "blocking_issue_id" => %{"type" => "string", "description" => "Story that blocks the other Story."},
            "blocked_issue_id" => %{"type" => "string", "description" => "Story that is blocked by blocking_issue_id."},
            "current_user" => %{"type" => "string", "description" => "TAPD user name required by the dependency API."},
            "src_field" => %{"type" => ["string", "null"], "description" => "Optional TAPD source date field. Defaults to due."},
            "dst_field" => %{"type" => ["string", "null"], "description" => "Optional TAPD destination date field. Defaults to begin."}
          }
        }
      ),
      tool_spec(
        @provider_diagnostics_tool,
        @provider_diagnostics_capability,
        "Run a fixed read-only TAPD provider diagnostics request without exposing arbitrary TAPD REST paths.",
        "read_only",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{}
        }
      )
    ]
  end

  @spec supported_tool_names() :: [String.t()]
  def supported_tool_names, do: Enum.map(tool_specs(), &Map.fetch!(&1, "name"))

  @spec typed_tool?(String.t() | nil) :: boolean()
  def typed_tool?(tool) when is_binary(tool), do: Enum.member?(supported_tool_names(), tool)
  def typed_tool?(_tool), do: false

  @spec execute(map(), String.t(), term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute(tracker, @issue_snapshot_tool, arguments, opts), do: issue_snapshot(tracker, arguments, opts)
  def execute(tracker, @move_issue_tool, arguments, opts), do: move_issue(tracker, arguments, opts)
  def execute(tracker, @upsert_workpad_tool, arguments, opts), do: upsert_workpad(tracker, arguments, opts)
  def execute(tracker, @attach_change_proposal_tool, arguments, opts), do: attach_change_proposal(tracker, arguments, opts)
  def execute(tracker, @upsert_comment_tool, arguments, opts), do: upsert_comment(tracker, arguments, opts)
  def execute(tracker, @create_follow_up_story_tool, arguments, opts), do: create_follow_up_story(tracker, arguments, opts)
  def execute(tracker, @read_story_relations_tool, arguments, opts), do: read_story_relations(tracker, arguments, opts)
  def execute(tracker, @add_story_relation_tool, arguments, opts), do: add_story_relation(tracker, arguments, opts)
  def execute(tracker, @read_story_dependencies_tool, arguments, opts), do: read_story_dependencies(tracker, arguments, opts)
  def execute(tracker, @save_story_dependency_tool, arguments, opts), do: save_story_dependency(tracker, arguments, opts)
  def execute(tracker, @provider_diagnostics_tool, arguments, opts), do: provider_diagnostics(tracker, arguments, opts)
  def execute(_tracker, _tool, _arguments, _opts), do: {:error, :unsupported_typed_tapd_tool}

  defp tool_spec(name, capability, description, side_effect, input_schema) do
    %{
      "name" => name,
      "description" => description,
      "inputSchema" => input_schema,
      @metadata_schema_version_key => @schema_version,
      @metadata_side_effect_key => side_effect,
      @metadata_risk_flags_key => @risk_flags,
      @metadata_workflow_capability_key => capability,
      @metadata_source_kind_key => @source_kind
    }
  end

  defp issue_snapshot(tracker, arguments, opts) do
    with {:ok, args} <- issue_snapshot_args(arguments),
         {:ok, issue} <- fetch_issue(tracker, args.issue_id, opts),
         {:ok, comments} <- maybe_fetch_comments(tracker, args, opts) do
      {:success,
       success_payload(%{
         "issue" => snapshot_issue(issue, comments),
         "workpad" => workpad_from_comments(comments, args.workpad_headings)
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp move_issue(tracker, arguments, opts) do
    with {:ok, args} <- move_issue_args(arguments),
         {:ok, issue} <- fetch_issue(tracker, args.issue_id, opts),
         :ok <- expected_current_state(issue, args.expected_current_state),
         {:ok, target_status} <- resolve_target_status(issue, args.state_name),
         {:ok, moved_issue} <- commit_story_move(tracker, issue, target_status, opts) do
      {:success, success_payload(%{"issue" => moved_issue})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp upsert_workpad(tracker, arguments, opts) do
    with {:ok, args} <- upsert_workpad_args(arguments),
         :ok <- validate_workpad_mode(args.mode),
         {:ok, comment} <- upsert_workpad_comment(tracker, args, opts) do
      {:success, success_payload(%{"comment" => comment})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp attach_change_proposal(tracker, arguments, opts) do
    with {:ok, args} <- attach_change_proposal_args(arguments),
         :ok <- validate_url(args.url),
         {:ok, comments} <- fetch_comments(tracker, args.issue_id, args.comment_limit, opts),
         {:ok, comment, existing?} <- upsert_change_proposal_link(tracker, comments, args, opts) do
      {:success,
       success_payload(%{
         "attachment" => %{
           "id" => "tapd-workpad:" <> Map.fetch!(comment, "id"),
           "title" => args.title || "Change proposal",
           "url" => args.url,
           "existing" => existing?,
           "storage" => "workpad_comment",
           "commentId" => Map.fetch!(comment, "id")
         }
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp upsert_comment(tracker, arguments, opts) do
    with {:ok, args} <- upsert_comment_args(arguments),
         {:ok, comment} <- upsert_general_comment(tracker, args, opts) do
      {:success, success_payload(%{"comment" => comment})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp create_follow_up_story(tracker, arguments, opts) do
    with {:ok, args} <- create_follow_up_story_args(arguments),
         {:ok, response} <- request(tracker, "POST", Paths.stories(), follow_up_story_params(args), opts),
         {:ok, data} <- Response.decode_success_envelope(Paths.stories(), response),
         {:ok, story} <- response_story(data, args) do
      {:success, success_payload(%{"story" => story})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp read_story_relations(tracker, arguments, opts) do
    with {:ok, issue_id} <- required_issue_id_args(arguments),
         {:ok, response} <- request(tracker, "GET", Paths.story_link_relations(), %{"story_id" => normalize_issue_id(issue_id)}, opts),
         {:ok, data} <- Response.decode_success_envelope(Paths.story_link_relations(), response),
         {:ok, relations} <- normalize_relation_list(data, Paths.story_link_relations()) do
      {:success, success_payload(%{"issueId" => normalize_issue_id(issue_id), "relations" => relations})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp add_story_relation(tracker, arguments, opts) do
    with {:ok, args} <- story_relation_args(arguments),
         {:ok, response} <-
           request(
             tracker,
             "POST",
             Paths.add_story_link_relations(),
             %{
               "src_story_id" => args.source_issue_id,
               "target_story_id" => args.target_issue_id
             },
             opts
           ),
         {:ok, data} <- Response.decode_success_envelope(Paths.add_story_link_relations(), response) do
      {:success,
       success_payload(%{
         "relation" => %{
           "sourceIssueId" => args.source_issue_id,
           "targetIssueId" => args.target_issue_id,
           "providerResult" => normalize_provider_result(data)
         }
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp read_story_dependencies(tracker, arguments, opts) do
    with {:ok, issue_id} <- required_issue_id_args(arguments),
         normalized_issue_id <- normalize_issue_id(issue_id),
         {:ok, response} <- request(tracker, "GET", Paths.story_time_relations(), %{"story_id" => normalized_issue_id}, opts),
         {:ok, data} <- Response.decode_success_envelope(Paths.story_time_relations(), response),
         {:ok, dependencies} <- normalize_relation_list(data, Paths.story_time_relations()) do
      {:success,
       success_payload(%{
         "issueId" => normalized_issue_id,
         "dependencies" => dependencies,
         "blockedBy" => blockers_from_time_relations(normalized_issue_id, dependencies)
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp save_story_dependency(tracker, arguments, opts) do
    with {:ok, args} <- story_dependency_args(arguments),
         {:ok, response} <- request(tracker, "POST", Paths.save_story_time_relations(), dependency_relation_params(args), opts),
         {:ok, data} <- Response.decode_success_envelope(Paths.save_story_time_relations(), response) do
      {:success,
       success_payload(%{
         "dependency" => %{
           "blockingIssueId" => args.blocking_issue_id,
           "blockedIssueId" => args.blocked_issue_id,
           "srcField" => args.src_field,
           "dstField" => args.dst_field,
           "providerResult" => normalize_provider_result(data)
         }
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp provider_diagnostics(tracker, arguments, opts) do
    with :ok <- validate_empty_args(arguments),
         {:ok, response} <- request(tracker, "GET", Paths.quickstart_testauth(), %{}, opts) do
      {:success,
       success_payload(%{
         "workspace" => %{
           "id" => Tracker.project_id(tracker),
           "url" => Tracker.project_url(tracker)
         },
         "auth" => response
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp fetch_issue(tracker, issue_id, opts) do
    request_fun = Keyword.get(opts, :request_fun, &Client.Request.default_request/1)
    normalized_id = normalize_issue_id(issue_id)

    case Client.fetch_stories_by_ids([normalized_id], tracker: tracker, request_fun: request_fun) do
      {:ok, [%Issue{} = issue | _rest]} ->
        {:ok, issue}

      {:ok, []} ->
        {:error, {:not_found, "TAPD Story #{normalized_id} was not found."}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_fetch_comments(_tracker, %{include_comments: false}, _opts), do: {:ok, []}

  defp maybe_fetch_comments(tracker, args, opts) do
    fetch_comments(tracker, args.issue_id, args.comment_limit, opts)
  end

  defp fetch_comments(tracker, issue_id, limit, opts) do
    with {:ok, body} <-
           request(
             tracker,
             "GET",
             Paths.comments(),
             %{
               "entry_type" => "stories",
               "entry_id" => normalize_issue_id(issue_id),
               "order" => "created asc",
               "limit" => limit
             },
             opts
           ),
         {:ok, data} <- Response.decode_success_envelope(Paths.comments(), body),
         {:ok, comments} <- normalize_comments(data, body) do
      {:ok, comments}
    end
  end

  defp request(tracker, method, path, params, opts) do
    Client.request(method, path, params,
      tracker: tracker,
      request_fun: Keyword.get(opts, :request_fun, &Client.Request.default_request/1)
    )
  end

  defp commit_story_move(_tracker, %Issue{state: state} = issue, state, _opts) do
    {:ok, moved_issue(issue, state)}
  end

  defp commit_story_move(tracker, %Issue{id: issue_id} = issue, target_status, opts) do
    case Client.request(
           "POST",
           Paths.stories(),
           %{"id" => issue_id, "status" => target_status},
           tracker: tracker,
           request_fun: Keyword.get(opts, :request_fun, &Client.Request.default_request/1)
         ) do
      {:ok, _body} ->
        {:ok, moved_issue(issue, target_status)}

      {:error, reason} ->
        {:error, normalize_story_update_error(reason, issue_id, target_status)}
    end
  end

  defp upsert_workpad_comment(tracker, %{comment_id: comment_id} = args, opts) when is_binary(comment_id) do
    case update_comment(tracker, comment_id, args.body, opts) do
      {:ok, comment} ->
        {:ok, comment}

      {:error, reason} ->
        maybe_recover_missing_workpad_comment(tracker, args, opts, reason)
    end
  end

  defp upsert_workpad_comment(tracker, args, opts) do
    upsert_workpad_comment_by_heading(tracker, args, opts)
  end

  defp upsert_workpad_comment_by_heading(tracker, args, opts) do
    with {:ok, comments} <- fetch_comments(tracker, args.issue_id, args.comment_limit, opts) do
      case workpad_from_comments(comments, args.match_headings) do
        %{"id" => comment_id} ->
          update_comment(tracker, comment_id, args.body, opts)

        _workpad ->
          create_comment(tracker, args.issue_id, args.body, opts)
      end
    end
  end

  defp maybe_recover_missing_workpad_comment(tracker, args, opts, reason) do
    if missing_tapd_comment?(reason) and is_binary(args.issue_id) do
      upsert_workpad_comment_by_heading(tracker, %{args | comment_id: nil}, opts)
    else
      {:error, reason}
    end
  end

  defp upsert_change_proposal_link(tracker, comments, args, opts) do
    case workpad_from_comments(comments, args.match_headings) do
      %{"body" => body, "id" => comment_id} = comment ->
        if String.contains?(body || "", args.url) do
          {:ok, Map.put(comment, "updated", false), true}
        else
          updated_body = append_change_proposal(body, args)
          with {:ok, comment} <- update_comment(tracker, comment_id, updated_body, opts), do: {:ok, comment, false}
        end

      _workpad ->
        body = canonical_workpad_body(args.heading, change_proposal_section(args))
        with {:ok, comment} <- create_comment(tracker, args.issue_id, body, opts), do: {:ok, comment, false}
    end
  end

  defp upsert_general_comment(tracker, %{comment_id: comment_id, body: body}, opts) when is_binary(comment_id) do
    update_comment(tracker, comment_id, body, opts)
  end

  defp upsert_general_comment(tracker, %{issue_id: issue_id, body: body}, opts) when is_binary(issue_id) do
    create_comment(tracker, issue_id, body, opts)
  end

  defp upsert_general_comment(_tracker, _args, _opts),
    do: {:error, {:invalid_arguments, "Either comment_id or issue_id is required."}}

  defp create_comment(tracker, issue_id, body, opts) do
    with {:ok, response} <-
           Client.request(
             "POST",
             Paths.comments(),
             %{"entry_type" => "stories", "entry_id" => normalize_issue_id(issue_id), "description" => body},
             tracker: tracker,
             request_fun: Keyword.get(opts, :request_fun, &Client.Request.default_request/1)
           ),
         {:ok, comment} <- response_comment(response, body) do
      {:ok, comment |> Map.put("created", true) |> Map.put("updated", false)}
    end
  end

  defp update_comment(tracker, comment_id, body, opts) do
    with {:ok, response} <-
           Client.request(
             "POST",
             Paths.comments(),
             %{"id" => comment_id, "description" => body},
             tracker: tracker,
             request_fun: Keyword.get(opts, :request_fun, &Client.Request.default_request/1)
           ),
         {:ok, comment} <- response_comment(response, body, comment_id) do
      {:ok, comment |> Map.put("created", false) |> Map.put("updated", true)}
    end
  end

  defp issue_snapshot_args(arguments) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, comment_limit} <- optional_integer(arguments, "comment_limit", @default_comment_limit, 1, 100),
         {:ok, workpad_heading} <- optional_string(arguments, "workpad_heading", @default_workpad_heading),
         {:ok, canonical_heading} <- canonical_workpad_heading(workpad_heading) do
      {:ok,
       %{
         issue_id: issue_id,
         include_comments: optional_boolean(arguments, "include_comments", true),
         include_attachments: optional_boolean(arguments, "include_attachments", true),
         comment_limit: comment_limit,
         workpad_headings: workpad_heading_candidates(canonical_heading)
       }}
    end
  end

  defp issue_snapshot_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with issue_id."}}

  defp move_issue_args(arguments) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, state_name} <- required_string(arguments, "state_name"),
         {:ok, expected_current_state} <- optional_nullable_string(arguments, "expected_current_state") do
      {:ok,
       %{
         issue_id: issue_id,
         state_name: state_name,
         expected_current_state: expected_current_state,
         reason: nullable_string(arguments, "reason")
       }}
    end
  end

  defp move_issue_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with issue_id and state_name."}}

  defp upsert_workpad_args(arguments) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, heading} <- required_string(arguments, "heading"),
         {:ok, body} <- required_string(arguments, "body"),
         {:ok, comment_id} <- optional_nullable_string(arguments, "comment_id"),
         {:ok, match_heading} <- optional_nullable_string(arguments, "match_heading"),
         {:ok, comment_limit} <- optional_integer(arguments, "comment_limit", @default_comment_limit, 1, 100),
         {:ok, canonical_heading} <- canonical_workpad_heading(heading) do
      {:ok,
       %{
         issue_id: issue_id,
         heading: canonical_heading,
         body: canonical_workpad_body(canonical_heading, body),
         comment_id: comment_id,
         match_headings: workpad_heading_candidates(match_heading || canonical_heading),
         mode: nullable_string(arguments, "mode") || "replace",
         comment_limit: comment_limit
       }}
    end
  end

  defp upsert_workpad_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with issue_id, heading, and body."}}

  defp attach_change_proposal_args(arguments) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, url} <- required_string(arguments, "url"),
         {:ok, title} <- optional_nullable_string(arguments, "title"),
         {:ok, workpad_heading} <- optional_string(arguments, "workpad_heading", @default_workpad_heading),
         {:ok, canonical_heading} <- canonical_workpad_heading(workpad_heading),
         {:ok, comment_limit} <- optional_integer(arguments, "comment_limit", @default_comment_limit, 1, 100) do
      {:ok,
       %{
         issue_id: issue_id,
         url: url,
         title: title,
         heading: canonical_heading,
         match_headings: workpad_heading_candidates(canonical_heading),
         comment_limit: comment_limit,
         repo_provider_kind: nullable_string(arguments, "repo_provider_kind"),
         repository: nullable_string(arguments, "repository"),
         change_proposal_id: optional_value(arguments, "change_proposal_id")
       }}
    end
  end

  defp attach_change_proposal_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with issue_id and url."}}

  defp upsert_comment_args(arguments) when is_map(arguments) do
    with {:ok, body} <- required_string(arguments, "body"),
         {:ok, issue_id} <- optional_nullable_string(arguments, "issue_id"),
         {:ok, comment_id} <- optional_nullable_string(arguments, "comment_id") do
      {:ok, %{issue_id: issue_id, comment_id: comment_id, body: body}}
    end
  end

  defp upsert_comment_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with body plus issue_id or comment_id."}}

  defp create_follow_up_story_args(arguments) when is_map(arguments) do
    with {:ok, source_issue_id} <- required_string(arguments, "source_issue_id"),
         {:ok, title} <- required_string(arguments, "title"),
         {:ok, description} <- required_string(arguments, "description"),
         {:ok, workitem_type_id} <- optional_nullable_string(arguments, "workitem_type_id"),
         {:ok, priority} <- optional_nullable_string(arguments, "priority"),
         {:ok, priority_label} <- optional_nullable_string(arguments, "priority_label"),
         {:ok, label} <- optional_nullable_string(arguments, "label") do
      {:ok,
       %{
         source_issue_id: normalize_issue_id(source_issue_id),
         title: title,
         description: description,
         workitem_type_id: workitem_type_id,
         priority: priority,
         priority_label: priority_label,
         label: label
       }}
    end
  end

  defp create_follow_up_story_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with source_issue_id, title, and description."}}

  defp required_issue_id_args(arguments) when is_map(arguments), do: required_string(arguments, "issue_id")
  defp required_issue_id_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with issue_id."}}

  defp story_relation_args(arguments) when is_map(arguments) do
    with {:ok, source_issue_id} <- required_string(arguments, "source_issue_id"),
         {:ok, target_issue_id} <- required_string(arguments, "target_issue_id") do
      {:ok,
       %{
         source_issue_id: normalize_issue_id(source_issue_id),
         target_issue_id: normalize_issue_id(target_issue_id)
       }}
    end
  end

  defp story_relation_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with source_issue_id and target_issue_id."}}

  defp story_dependency_args(arguments) when is_map(arguments) do
    with {:ok, blocking_issue_id} <- required_string(arguments, "blocking_issue_id"),
         {:ok, blocked_issue_id} <- required_string(arguments, "blocked_issue_id"),
         {:ok, current_user} <- required_string(arguments, "current_user"),
         {:ok, src_field} <- optional_string(arguments, "src_field", "due"),
         {:ok, dst_field} <- optional_string(arguments, "dst_field", "begin") do
      {:ok,
       %{
         blocking_issue_id: normalize_issue_id(blocking_issue_id),
         blocked_issue_id: normalize_issue_id(blocked_issue_id),
         current_user: current_user,
         src_field: src_field,
         dst_field: dst_field
       }}
    end
  end

  defp story_dependency_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with blocking_issue_id, blocked_issue_id, and current_user."}}

  defp validate_empty_args(nil), do: :ok
  defp validate_empty_args(arguments) when is_map(arguments) and map_size(arguments) == 0, do: :ok
  defp validate_empty_args(_arguments), do: {:error, {:invalid_arguments, "Expected an empty object."}}

  defp snapshot_issue(%Issue{} = issue, comments) do
    workflow = workflow_map(issue.workflow)

    %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "title" => issue.title,
      "description" => issue.description,
      "url" => issue.url,
      "state" => state_payload(issue.state, issue.lifecycle_phase),
      "labels" => Enum.map(issue.labels, &%{"name" => &1}),
      "attachments" => [],
      "comments" => comments,
      "branchName" => issue.branch_name,
      "workitemTypeId" => issue.workitem_type_id,
      "blockedBy" => Enum.map(issue.blocked_by, &string_key_map/1),
      "workflow" => workflow,
      "states" => workflow_states(workflow)
    }
  end

  defp moved_issue(%Issue{} = issue, target_status) do
    phase =
      issue.workflow
      |> workflow_map()
      |> Map.get("statePhaseMap", %{})
      |> Map.get(target_status)

    %{
      "id" => issue.id,
      "identifier" => issue.identifier,
      "state" => state_payload(target_status, phase)
    }
  end

  defp state_payload(state, phase) do
    %{
      "id" => state,
      "name" => state,
      "type" => phase
    }
  end

  defp follow_up_story_params(args) do
    %{
      "name" => args.title,
      "description" => args.description,
      "parent_id" => args.source_issue_id,
      "workitem_type_id" => args.workitem_type_id,
      "priority" => args.priority,
      "priority_label" => args.priority_label,
      "label" => args.label
    }
    |> drop_nil_values()
  end

  defp dependency_relation_params(args) do
    %{
      "relations[0][workitem_id]" => args.blocking_issue_id,
      "relations[0][dst_workitem_id]" => args.blocked_issue_id,
      "relations[0][src_field]" => args.src_field,
      "relations[0][dst_field]" => args.dst_field,
      "current_user" => args.current_user
    }
  end

  defp response_story(data, args) do
    story =
      data
      |> unwrap_story_data()
      |> string_key_map()

    id = story["id"]

    if is_binary(id) or is_integer(id) do
      {:ok,
       %{
         "id" => to_string(id),
         "identifier" => "TAPD-" <> to_string(id),
         "title" => story["name"] || args.title,
         "description" => story["description"] || args.description,
         "parentId" => story["parent_id"] || args.source_issue_id,
         "workitemTypeId" => story["workitem_type_id"] || args.workitem_type_id,
         "url" => story["url"]
       }
       |> drop_nil_values()}
    else
      {:error, {:unexpected_tapd_payload, Paths.stories(), data}}
    end
  end

  defp unwrap_story_data(%{"Story" => %{} = story}), do: story
  defp unwrap_story_data(%{Story: %{} = story}), do: story
  defp unwrap_story_data(%{} = data), do: data
  defp unwrap_story_data(other), do: other

  defp normalize_relation_list(data, _path) when is_list(data) do
    {:ok, Enum.map(data, &normalize_relation_entry/1)}
  end

  defp normalize_relation_list(data, path), do: {:error, {:unexpected_tapd_payload, path, data}}

  defp normalize_relation_entry(%{"WorkitemTimeRelation" => %{} = relation}), do: normalize_relation_entry(relation)
  defp normalize_relation_entry(%{WorkitemTimeRelation: %{} = relation}), do: normalize_relation_entry(relation)
  defp normalize_relation_entry(%{"StoryLinkRelation" => %{} = relation}), do: normalize_relation_entry(relation)
  defp normalize_relation_entry(%{StoryLinkRelation: %{} = relation}), do: normalize_relation_entry(relation)
  defp normalize_relation_entry(%{} = relation), do: string_key_map(relation)
  defp normalize_relation_entry(other), do: %{"value" => inspect(other)}

  defp blockers_from_time_relations(issue_id, relations) when is_list(relations) do
    relations
    |> Enum.flat_map(fn relation ->
      relation_story_id = nullable_string(relation, "dst_workitem_id")
      blocker_id = nullable_string(relation, "workitem_id")

      if relation_story_id == issue_id and is_binary(blocker_id) and blocker_id != issue_id do
        [%{"id" => blocker_id, "identifier" => "TAPD-" <> blocker_id}]
      else
        []
      end
    end)
    |> Enum.uniq_by(&Map.get(&1, "id"))
  end

  defp normalize_provider_result(data) when is_map(data), do: string_key_map(data)
  defp normalize_provider_result(data) when is_list(data), do: Enum.map(data, &normalize_provider_result/1)
  defp normalize_provider_result(data), do: data

  defp workflow_states(%{"rawStateByRouteKey" => route_states, "statePhaseMap" => state_phase_map})
       when is_map(route_states) do
    route_states
    |> Enum.map(fn {route_key, raw_status} ->
      %{
        "id" => raw_status,
        "name" => raw_status,
        "type" => Map.get(state_phase_map, raw_status),
        "routeKey" => route_key
      }
    end)
    |> Enum.sort_by(&Map.get(&1, "routeKey"))
  end

  defp workflow_states(_workflow), do: []

  defp expected_current_state(_issue, nil), do: :ok

  defp expected_current_state(%Issue{} = issue, expected) do
    current_values =
      [issue.state, issue.lifecycle_phase]
      |> Enum.concat(route_keys_for_status(issue.workflow, issue.state))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.member?(current_values, expected) do
      :ok
    else
      {:error,
       {:state_conflict,
        %{
          "message" => "TAPD Story state changed before transition.",
          "expected" => expected,
          "actual" => issue.state,
          "actualLifecyclePhase" => issue.lifecycle_phase
        }}}
    end
  end

  defp resolve_target_status(%Issue{} = issue, state_name) do
    workflow = workflow_map(issue.workflow)
    route_states = Map.get(workflow, "rawStateByRouteKey", %{})
    state_phase_map = Map.get(workflow, "statePhaseMap", %{})

    cond do
      state_name in Map.values(route_states) ->
        {:ok, state_name}

      Map.has_key?(route_states, state_name) ->
        {:ok, Map.fetch!(route_states, state_name)}

      true ->
        resolve_status_by_lifecycle_phase(state_phase_map, state_name)
    end
  end

  defp resolve_status_by_lifecycle_phase(state_phase_map, phase) when is_map(state_phase_map) do
    matches =
      state_phase_map
      |> Enum.filter(fn {_status, lifecycle_phase} -> lifecycle_phase == phase end)
      |> Enum.map(fn {status, _phase} -> status end)
      |> Enum.uniq()

    case matches do
      [status] -> {:ok, status}
      [] -> {:error, {:unknown_state, "No TAPD route, raw status, or lifecycle phase matched #{inspect(phase)}."}}
      matches -> {:error, {:ambiguous_state, "Lifecycle phase #{inspect(phase)} maps to multiple TAPD statuses: #{Enum.join(matches, ", ")}."}}
    end
  end

  defp route_keys_for_status(workflow, status) do
    workflow
    |> workflow_map()
    |> Map.get("rawStateByRouteKey", %{})
    |> Enum.flat_map(fn
      {route_key, ^status} -> [route_key]
      _entry -> []
    end)
  end

  defp normalize_comments(data, body) when is_list(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case normalize_comment_entry(entry) do
        {:ok, comment} -> {:cont, {:ok, acc ++ [comment]}}
        :error -> {:halt, {:error, {:unexpected_tapd_payload, Paths.comments(), body}}}
      end
    end)
  end

  defp normalize_comments(_data, body), do: {:error, {:unexpected_tapd_payload, Paths.comments(), body}}

  defp normalize_comment_entry(%{"Comment" => %{} = comment}), do: normalize_comment_entry(comment)
  defp normalize_comment_entry(%{Comment: %{} = comment}), do: normalize_comment_entry(comment)

  defp normalize_comment_entry(%{} = comment) do
    normalized = string_key_map(comment)
    id = normalized["id"]
    body = normalized["description"] || normalized["body"] || ""

    if is_binary(id) or is_integer(id) do
      {:ok,
       %{
         "id" => to_string(id),
         "body" => body,
         "createdAt" => normalized["created"] || normalized["created_at"],
         "updatedAt" => normalized["modified"] || normalized["updated"] || normalized["updated_at"],
         "user" => %{"name" => normalized["author"] || normalized["owner"] || normalized["creator"]}
       }}
    else
      :error
    end
  end

  defp normalize_comment_entry(_entry), do: :error

  defp workpad_from_comments(comments, headings) do
    Enum.find_value(comments, fn comment ->
      body = Map.get(comment, "body") || ""

      cond do
        Enum.any?(headings, &starts_with_heading?(body, &1)) ->
          Map.put(comment, "matchedBy", "heading")

        legacy_workpad_body?(body) ->
          Map.put(comment, "matchedBy", "legacy_markers")

        true ->
          nil
      end
    end)
  end

  defp starts_with_heading?(body, heading) when is_binary(body) and is_binary(heading) do
    String.starts_with?(String.trim_leading(body), heading)
  end

  defp legacy_workpad_body?(body) when is_binary(body) do
    Enum.all?(@legacy_workpad_markers, &String.contains?(body, &1))
  end

  defp response_comment(response, fallback_body, fallback_id \\ nil) do
    with {:ok, data} <- Response.decode_success_envelope(Paths.comments(), response),
         {:ok, comment} <- response_comment_data(data, fallback_body, fallback_id) do
      {:ok, comment}
    end
  end

  defp response_comment_data(data, fallback_body, fallback_id) do
    candidate =
      data
      |> unwrap_comment_data()
      |> string_key_map()

    id = candidate["id"] || fallback_id

    if is_binary(id) or is_integer(id) do
      {:ok,
       %{
         "id" => to_string(id),
         "url" => candidate["url"],
         "body" => candidate["description"] || candidate["body"] || fallback_body
       }}
    else
      {:error, {:unexpected_tapd_payload, Paths.comments(), data}}
    end
  end

  defp unwrap_comment_data(%{"Comment" => %{} = comment}), do: comment
  defp unwrap_comment_data(%{Comment: %{} = comment}), do: comment
  defp unwrap_comment_data(%{} = data), do: data
  defp unwrap_comment_data(other), do: other

  defp append_change_proposal(body, args) do
    body
    |> to_string()
    |> String.trim_trailing()
    |> Kernel.<>("\n\n" <> change_proposal_section(args))
  end

  defp change_proposal_section(args) do
    title = args.title || "Change proposal"

    "- [#{title}](#{args.url})"
    |> then(&("### Change Proposal\n\n" <> &1))
  end

  defp canonical_workpad_heading(heading) when is_binary(heading) do
    case String.trim(heading) do
      "" -> {:error, {:invalid_arguments, "Workpad heading must not be blank."}}
      "#" <> _rest = markdown_heading -> {:ok, markdown_heading}
      title -> {:ok, "## " <> title}
    end
  end

  defp canonical_workpad_body(heading, body) do
    trimmed_body = String.trim_leading(body)

    if String.starts_with?(trimmed_body, heading) do
      trimmed_body
    else
      heading <> "\n\n" <> trimmed_body
    end
  end

  defp workpad_heading_candidates(heading) do
    {:ok, canonical} = canonical_workpad_heading(heading)

    [
      canonical,
      String.trim_leading(canonical, "#") |> String.trim() |> then(&("## " <> &1))
    ]
    |> Enum.uniq()
  end

  defp validate_workpad_mode("replace"), do: :ok
  defp validate_workpad_mode(nil), do: :ok
  defp validate_workpad_mode(mode), do: {:error, {:invalid_arguments, "Unsupported workpad mode #{inspect(mode)}."}}

  defp validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _uri -> {:error, {:invalid_arguments, "Change proposal URL must be an absolute http(s) URL."}}
    end
  end

  defp normalize_story_update_error(reason, story_id, target_status) do
    SymphonyElixir.Tracker.Tapd.Client.Errors.classify_story_update_error(reason, story_id, target_status)
  end

  defp missing_tapd_comment?(%SymphonyElixir.Tracker.Error{
         details: %{source_reason: {:tapd_http_status, 422, %{"info" => info}}}
       })
       when is_binary(info) do
    String.contains?(info, "comment") and String.contains?(info, "not exist")
  end

  defp missing_tapd_comment?(_reason), do: false

  defp required_string(arguments, key) do
    case nullable_string(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp optional_string(arguments, key, default) do
    case nullable_string(arguments, key) do
      nil -> {:ok, default}
      value -> {:ok, value}
    end
  end

  defp optional_nullable_string(arguments, key), do: {:ok, nullable_string(arguments, key)}

  defp nullable_string(arguments, key) do
    arguments
    |> optional_value(key)
    |> case do
      nil -> nil
      value when is_binary(value) -> normalize_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> normalize_string()
      value when is_integer(value) -> Integer.to_string(value)
      _value -> nil
    end
  end

  defp optional_integer(arguments, key, default, min, max) do
    value = optional_value(arguments, key)

    cond do
      is_nil(value) ->
        {:ok, default}

      is_integer(value) and value >= min and value <= max ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {integer, ""} when integer >= min and integer <= max -> {:ok, integer}
          _parse -> {:error, {:invalid_arguments, "#{key} must be an integer between #{min} and #{max}."}}
        end

      true ->
        {:error, {:invalid_arguments, "#{key} must be an integer between #{min} and #{max}."}}
    end
  end

  defp optional_boolean(arguments, key, default) do
    case optional_value(arguments, key) do
      nil -> default
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _value -> default
    end
  end

  defp optional_value(arguments, key) do
    with :error <- fetch_optional_value(arguments, key),
         :error <- fetch_optional_value(arguments, camelize(key)),
         :error <- fetch_atom_optional_value(arguments, atom_key(key)) do
      nil
    else
      {:ok, value} -> value
    end
  end

  defp fetch_optional_value(arguments, key) when is_binary(key) do
    if Map.has_key?(arguments, key), do: {:ok, Map.get(arguments, key)}, else: :error
  end

  defp fetch_atom_optional_value(_arguments, nil), do: :error
  defp fetch_atom_optional_value(arguments, key), do: if(Map.has_key?(arguments, key), do: {:ok, Map.get(arguments, key)}, else: :error)

  defp atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp camelize(key) when is_binary(key) do
    [first | rest] = String.split(key, "_")
    first <> Enum.map_join(rest, "", &String.capitalize/1)
  end

  defp normalize_issue_id("TAPD-" <> id), do: id
  defp normalize_issue_id(issue_id) when is_binary(issue_id), do: String.trim(issue_id)

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp success_payload(payload) when is_map(payload), do: payload

  defp typed_failure(reason) do
    {:failure,
     %{
       "error" => %{
         "message" => "TAPD typed tool execution failed.",
         "reason" => inspect(reason)
       }
     }}
  end

  defp workflow_map(%{__struct__: SymphonyElixir.Workflow.Effective} = workflow) do
    workflow
    |> SymphonyElixir.Workflow.Effective.to_map()
    |> workflow_map()
  end

  defp workflow_map(workflow) when is_map(workflow) do
    %{
      "workitemTypeId" => Map.get(workflow, :workitem_type_id) || Map.get(workflow, "workitem_type_id"),
      "activeStates" => Map.get(workflow, :active_states) || Map.get(workflow, "active_states") || [],
      "terminalStates" => Map.get(workflow, :terminal_states) || Map.get(workflow, "terminal_states") || [],
      "statePhaseMap" => string_key_map(Map.get(workflow, :state_phase_map) || Map.get(workflow, "state_phase_map") || %{}),
      "rawStateByRouteKey" =>
        workflow
        |> Map.get(:raw_state_by_route_key, Map.get(workflow, "raw_state_by_route_key", %{}))
        |> route_key_map()
    }
  end

  defp route_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp route_key_map(_map), do: %{}

  defp string_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp string_key_map(_value), do: %{}

  defp drop_nil_values(map) when is_map(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
