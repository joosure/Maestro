defmodule SymphonyElixir.Tracker.Linear.ToolExecutor.TypedTools do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.MetadataContract
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.Linear.Client
  alias SymphonyElixir.Workflow.CapabilityNames

  @source_kind Kinds.linear()
  @schema_version "1"
  @risk_flags ["external_network", "secret_access", "privileged_api"]
  @metadata_schema_version_key MetadataContract.schema_version()
  @metadata_side_effect_key MetadataContract.side_effect()
  @metadata_risk_flags_key MetadataContract.risk_flags()
  @metadata_workflow_capability_key MetadataContract.workflow_capability()
  @metadata_source_kind_key MetadataContract.source_kind()

  @issue_snapshot_tool "linear_issue_snapshot"
  @move_issue_tool "linear_move_issue"
  @upsert_workpad_tool "linear_upsert_workpad"
  @attach_change_proposal_tool "linear_attach_change_proposal"
  @upsert_comment_tool "linear_upsert_comment"
  @prepare_file_upload_tool "linear_prepare_file_upload"
  @provider_diagnostics_tool "linear_provider_diagnostics"

  @issue_snapshot_capability CapabilityNames.tracker_issue_snapshot()
  @move_issue_capability CapabilityNames.tracker_move_issue()
  @upsert_workpad_capability CapabilityNames.tracker_upsert_workpad()
  @attach_change_proposal_capability CapabilityNames.tracker_attach_change_proposal()
  @upsert_comment_capability CapabilityNames.tracker_upsert_comment()
  @prepare_file_upload_capability CapabilityNames.tracker_prepare_file_upload()
  @provider_diagnostics_capability CapabilityNames.tracker_provider_diagnostics()

  @issue_snapshot_query """
  query SymphonyLinearIssueSnapshot($issueId: String!, $commentFirst: Int!) {
    issue(id: $issueId) {
      id
      identifier
      title
      description
      branchName
      url
      state {
        id
        name
        type
      }
      team {
        states {
          nodes {
            id
            name
            type
          }
        }
      }
      labels {
        nodes {
          name
        }
      }
      attachments {
        nodes {
          id
          title
          url
          sourceType
        }
      }
      comments(first: $commentFirst) {
        nodes {
          id
          body
          resolvedAt
          createdAt
          updatedAt
          user {
            name
          }
        }
      }
    }
  }
  """

  @issue_team_states_query """
  query SymphonyLinearIssueTeamStates($issueId: String!) {
    issue(id: $issueId) {
      id
      identifier
      state {
        id
        name
        type
      }
      team {
        states {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  }
  """

  @move_issue_mutation """
  mutation SymphonyLinearMoveIssue($issueId: String!, $stateId: String!) {
    issueUpdate(id: $issueId, input: {stateId: $stateId}) {
      success
      issue {
        id
        identifier
        state {
          id
          name
          type
        }
      }
    }
  }
  """

  @workpad_comments_query """
  query SymphonyLinearWorkpadComments($issueId: String!, $first: Int!) {
    issue(id: $issueId) {
      id
      comments(first: $first) {
        nodes {
          id
          body
          resolvedAt
          createdAt
          updatedAt
          user {
            name
          }
        }
      }
    }
  }
  """

  @create_comment_mutation """
  mutation SymphonyLinearCreateWorkpad($issueId: String!, $body: String!) {
    commentCreate(input: {issueId: $issueId, body: $body}) {
      success
      comment {
        id
        body
        url
      }
    }
  }
  """

  @update_comment_mutation """
  mutation SymphonyLinearUpdateWorkpad($commentId: String!, $body: String!) {
    commentUpdate(id: $commentId, input: {body: $body}) {
      success
      comment {
        id
        body
        url
      }
    }
  }
  """

  @issue_attachments_query """
  query SymphonyLinearIssueAttachments($issueId: String!) {
    issue(id: $issueId) {
      id
      attachments {
        nodes {
          id
          title
          url
          sourceType
        }
      }
    }
  }
  """

  @attach_github_pr_mutation """
  mutation SymphonyLinearAttachGitHubPR($issueId: String!, $url: String!, $title: String) {
    attachmentLinkGitHubPR(
      issueId: $issueId
      url: $url
      title: $title
      linkKind: links
    ) {
      success
      attachment {
        id
        title
        url
      }
    }
  }
  """

  @attach_url_mutation """
  mutation SymphonyLinearAttachURL($issueId: String!, $url: String!, $title: String) {
    attachmentCreate(input: {issueId: $issueId, url: $url, title: $title}) {
      success
      attachment {
        id
        title
        url
      }
    }
  }
  """

  @file_upload_mutation """
  mutation SymphonyLinearPrepareFileUpload($filename: String!, $contentType: String!, $size: Int!, $makePublic: Boolean) {
    fileUpload(filename: $filename, contentType: $contentType, size: $size, makePublic: $makePublic) {
      success
      uploadFile {
        uploadUrl
        assetUrl
        headers {
          key
          value
        }
      }
    }
  }
  """

  @provider_diagnostics_query """
  query SymphonyLinearProviderDiagnostics {
    viewer {
      id
      name
    }
  }
  """

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      tool_spec(
        @issue_snapshot_tool,
        @issue_snapshot_capability,
        "Read a Linear issue snapshot, including state, labels, attachments, comments, team states, and active workpad candidates.",
        "read_only",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Linear issue id or identifier."},
            "include_comments" => %{"type" => "boolean", "description" => "Whether to include issue comments."},
            "include_attachments" => %{"type" => "boolean", "description" => "Whether to include issue attachments."},
            "comment_limit" => %{"type" => "integer", "description" => "Maximum comments to read."},
            "workpad_heading" => %{"type" => "string", "description" => "Workpad heading used to identify the active workpad comment."}
          }
        }
      ),
      tool_spec(
        @move_issue_tool,
        @move_issue_capability,
        "Move a Linear issue to a named state without exposing Linear GraphQL state-id resolution to the agent.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "state_name"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Linear issue id or identifier."},
            "state_name" => %{"type" => "string", "description" => "Destination Linear state name."},
            "expected_current_state" => %{"type" => ["string", "null"], "description" => "Optional optimistic current state check."},
            "reason" => %{"type" => ["string", "null"], "description" => "Optional human-readable reason for the transition."}
          }
        }
      ),
      tool_spec(
        @upsert_workpad_tool,
        @upsert_workpad_capability,
        "Create or update the single Linear workpad comment for a workflow run. The heading is the workpad identity; the executor canonicalizes the stored comment body.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "heading", "body"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Linear issue id or identifier."},
            "heading" => %{"type" => "string", "description" => "Workpad title or Markdown heading used as the stable comment identity."},
            "body" => %{"type" => "string", "description" => "Workpad body. The executor prefixes the canonical heading if it is omitted."},
            "comment_id" => %{"type" => ["string", "null"], "description" => "Existing Linear comment id to update."},
            "match_heading" => %{"type" => ["string", "null"], "description" => "Optional alternate workpad title or Markdown heading used to find an existing workpad."},
            "mode" => %{"type" => ["string", "null"], "description" => "Upsert mode. The current contract supports replace."}
          }
        }
      ),
      tool_spec(
        @attach_change_proposal_tool,
        @attach_change_proposal_capability,
        "Attach a repository-backed change proposal URL, such as a GitHub pull request, to a Linear issue.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["issue_id", "url"],
          "properties" => %{
            "issue_id" => %{"type" => "string", "description" => "Linear issue id or identifier."},
            "url" => %{"type" => "string", "description" => "Absolute change proposal URL."},
            "title" => %{"type" => ["string", "null"], "description" => "Optional attachment title."},
            "repo_provider_kind" => %{"type" => ["string", "null"], "description" => "Optional repo provider kind."},
            "repository" => %{"type" => ["string", "null"], "description" => "Optional provider repository handle."},
            "change_proposal_id" => %{"type" => ["string", "number", "integer", "null"], "description" => "Optional provider change proposal id."}
          }
        }
      ),
      tool_spec(
        @upsert_comment_tool,
        @upsert_comment_capability,
        "Create a Linear issue comment or update a specific existing comment without exposing raw GraphQL comment mutation names.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["body"],
          "properties" => %{
            "issue_id" => %{"type" => ["string", "null"], "description" => "Linear issue id or identifier. Required when comment_id is omitted."},
            "comment_id" => %{"type" => ["string", "null"], "description" => "Existing Linear comment id to update. When present, the tool updates this comment."},
            "body" => %{"type" => "string", "description" => "Complete comment body to create or replace."},
            "asset_urls" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "Optional uploaded Linear asset URLs to append to the comment body."}
          }
        }
      ),
      tool_spec(
        @prepare_file_upload_tool,
        @prepare_file_upload_capability,
        "Prepare a Linear signed file upload without exposing the raw fileUpload GraphQL mutation.",
        "write",
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["filename", "content_type", "size"],
          "properties" => %{
            "filename" => %{"type" => "string", "description" => "Filename Linear should associate with the uploaded asset."},
            "content_type" => %{"type" => "string", "description" => "MIME content type for the file upload."},
            "size" => %{"type" => "integer", "description" => "File size in bytes."},
            "make_public" => %{"type" => ["boolean", "null"], "description" => "Whether Linear should generate a public asset URL."}
          }
        }
      ),
      tool_spec(
        @provider_diagnostics_tool,
        @provider_diagnostics_capability,
        "Run a fixed read-only Linear provider diagnostics query without exposing arbitrary GraphQL.",
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

  @spec execute(map(), String.t(), term(), keyword()) ::
          SymphonyElixir.Tracker.Adapter.tool_result()
  def execute(tracker, @issue_snapshot_tool, arguments, opts), do: issue_snapshot(tracker, arguments, opts)
  def execute(tracker, @move_issue_tool, arguments, opts), do: move_issue(tracker, arguments, opts)
  def execute(tracker, @upsert_workpad_tool, arguments, opts), do: upsert_workpad(tracker, arguments, opts)
  def execute(tracker, @attach_change_proposal_tool, arguments, opts), do: attach_change_proposal(tracker, arguments, opts)
  def execute(tracker, @upsert_comment_tool, arguments, opts), do: upsert_comment(tracker, arguments, opts)
  def execute(tracker, @prepare_file_upload_tool, arguments, opts), do: prepare_file_upload(tracker, arguments, opts)
  def execute(tracker, @provider_diagnostics_tool, arguments, opts), do: provider_diagnostics(tracker, arguments, opts)
  def execute(_tracker, _tool, _arguments, _opts), do: {:error, :unsupported_typed_linear_tool}

  @spec typed_tool?(String.t() | nil) :: boolean()
  def typed_tool?(tool) when is_binary(tool), do: Enum.member?(supported_tool_names(), tool)
  def typed_tool?(_tool), do: false

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
         {:ok, response} <- graphql(tracker, @issue_snapshot_query, %{issueId: args.issue_id, commentFirst: args.comment_limit}, opts, :issue_snapshot),
         {:ok, issue} <- response_issue(response) do
      {:success,
       success_payload(%{
         "issue" => snapshot_issue(issue, args),
         "workpad" => workpad_from_issue(issue, args.workpad_heading)
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp move_issue(tracker, arguments, opts) do
    with {:ok, args} <- move_issue_args(arguments),
         {:ok, response} <- graphql(tracker, @issue_team_states_query, %{issueId: args.issue_id}, opts, :move_issue),
         {:ok, issue} <- response_issue(response),
         :ok <- expected_current_state(issue, args.expected_current_state),
         {:ok, state} <- resolve_state(issue, args.state_name) do
      if get_in(issue, ["state", "name"]) == args.state_name do
        {:success, success_payload(%{"issue" => moved_issue(issue, state)})}
      else
        commit_issue_move(tracker, args.issue_id, state, opts)
      end
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
         {:ok, response} <- graphql(tracker, @issue_attachments_query, %{issueId: args.issue_id}, opts, :attach_change_proposal),
         {:ok, issue} <- response_issue(response) do
      case existing_attachment(issue, args.url) do
        nil -> create_attachment(tracker, args, opts)
        attachment -> {:success, success_payload(%{"attachment" => Map.put(attachment, "existing", true)})}
      end
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

  defp prepare_file_upload(tracker, arguments, opts) do
    with {:ok, args} <- prepare_file_upload_args(arguments),
         {:ok, response} <- graphql(tracker, @file_upload_mutation, file_upload_variables(args), opts, :prepare_file_upload),
         {:ok, upload_file} <- mutation_upload_file(response, ["data", "fileUpload"], :file_upload_failed) do
      {:success, success_payload(%{"upload_file" => upload_file})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp provider_diagnostics(tracker, arguments, opts) do
    with :ok <- validate_empty_args(arguments),
         {:ok, response} <- graphql(tracker, @provider_diagnostics_query, %{}, opts, :provider_diagnostics),
         {:ok, viewer} <- response_viewer(response) do
      {:success, success_payload(%{"viewer" => viewer})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp commit_issue_move(tracker, issue_id, state, opts) do
    with {:ok, response} <- graphql(tracker, @move_issue_mutation, %{issueId: issue_id, stateId: Map.fetch!(state, "id")}, opts, :move_issue),
         {:ok, issue} <- mutation_issue(response, ["data", "issueUpdate"], :issue_update_failed) do
      {:success, success_payload(%{"issue" => issue})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp upsert_general_comment(tracker, %{comment_id: comment_id, body: body}, opts) when is_binary(comment_id) do
    update_general_comment(tracker, comment_id, body, opts)
  end

  defp upsert_general_comment(tracker, %{issue_id: issue_id, body: body}, opts) when is_binary(issue_id) do
    create_general_comment(tracker, issue_id, body, opts)
  end

  defp upsert_general_comment(_tracker, _args, _opts), do: {:error, {:invalid_arguments, "Either comment_id or issue_id is required."}}

  defp update_general_comment(tracker, comment_id, body, opts) do
    variables = %{commentId: comment_id, body: body}

    with {:ok, response} <- graphql(tracker, @update_comment_mutation, variables, opts, :upsert_comment),
         {:ok, comment} <- mutation_comment(response, ["data", "commentUpdate"], :comment_update_failed) do
      {:ok, comment |> Map.put("updated", true) |> Map.put("created", false)}
    end
  end

  defp create_general_comment(tracker, issue_id, body, opts) do
    with {:ok, response} <- graphql(tracker, @create_comment_mutation, %{issueId: issue_id, body: body}, opts, :upsert_comment),
         {:ok, comment} <- mutation_comment(response, ["data", "commentCreate"], :comment_create_failed) do
      {:ok, comment |> Map.put("updated", false) |> Map.put("created", true)}
    end
  end

  defp upsert_workpad_comment(tracker, %{comment_id: comment_id} = args, opts) when is_binary(comment_id) do
    update_workpad_comment(tracker, comment_id, args.body, opts)
  end

  defp upsert_workpad_comment(tracker, args, opts) do
    with {:ok, response} <- graphql(tracker, @workpad_comments_query, %{issueId: args.issue_id, first: args.comment_limit}, opts, :upsert_workpad),
         {:ok, issue} <- response_issue(response) do
      case workpad_from_issue(issue, args.match_headings) do
        %{"id" => comment_id} when is_binary(comment_id) ->
          update_workpad_comment(tracker, comment_id, args.body, opts)

        _workpad ->
          create_workpad_comment(tracker, args.issue_id, args.body, opts)
      end
    end
  end

  defp update_workpad_comment(tracker, comment_id, body, opts) do
    variables = %{commentId: comment_id, body: body}

    with {:ok, response} <- graphql(tracker, @update_comment_mutation, variables, opts, :upsert_workpad),
         {:ok, comment} <- mutation_comment(response, ["data", "commentUpdate"], :comment_update_failed) do
      {:ok, comment |> Map.put("updated", true) |> Map.put("created", false)}
    end
  end

  defp create_workpad_comment(tracker, issue_id, body, opts) do
    with {:ok, response} <- graphql(tracker, @create_comment_mutation, %{issueId: issue_id, body: body}, opts, :upsert_workpad),
         {:ok, comment} <- mutation_comment(response, ["data", "commentCreate"], :comment_create_failed) do
      {:ok, comment |> Map.put("updated", false) |> Map.put("created", true)}
    end
  end

  defp create_attachment(tracker, args, opts) do
    mutation =
      if github_pr_url?(args.url) do
        @attach_github_pr_mutation
      else
        @attach_url_mutation
      end

    result_key =
      if github_pr_url?(args.url) do
        "attachmentLinkGitHubPR"
      else
        "attachmentCreate"
      end

    variables = %{issueId: args.issue_id, url: args.url, title: args.title}

    with {:ok, response} <- graphql(tracker, mutation, variables, opts, :attach_change_proposal),
         {:ok, attachment} <- mutation_attachment(response, ["data", result_key], :attachment_create_failed) do
      {:success, success_payload(%{"attachment" => Map.put(attachment, "existing", false)})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp file_upload_variables(args) do
    %{
      filename: args.filename,
      contentType: args.content_type,
      size: args.size,
      makePublic: args.make_public
    }
  end

  defp graphql(tracker, query, variables, opts, operation) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)
    client_opts = if Keyword.has_key?(opts, :linear_client), do: [], else: [tracker: tracker, operation: operation]

    case linear_client.(query, variables, client_opts) do
      {:ok, %{"errors" => errors} = response} when is_list(errors) and errors != [] ->
        {:error, {:provider_validation_failed, response}}

      {:ok, %{errors: errors} = response} when is_list(errors) and errors != [] ->
        {:error, {:provider_validation_failed, response}}

      {:ok, response} when is_map(response) ->
        {:ok, response}

      {:ok, response} ->
        {:error, {:provider_unknown_payload, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp issue_snapshot_args(arguments) when is_map(arguments) do
    with {:ok, issue_id} <- required_string(arguments, "issue_id"),
         {:ok, comment_limit} <- optional_integer(arguments, "comment_limit", 50, 1, 100),
         {:ok, workpad_heading} <- optional_string(arguments, "workpad_heading", "## Claude Code Workpad") do
      {:ok,
       %{
         issue_id: issue_id,
         include_comments: optional_boolean(arguments, "include_comments", true),
         include_attachments: optional_boolean(arguments, "include_attachments", true),
         comment_limit: comment_limit,
         workpad_heading: workpad_heading
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
         {:ok, comment_limit} <- optional_integer(arguments, "comment_limit", 50, 1, 100),
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
         {:ok, title} <- optional_nullable_string(arguments, "title") do
      {:ok,
       %{
         issue_id: issue_id,
         url: url,
         title: title,
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
         {:ok, comment_id} <- optional_nullable_string(arguments, "comment_id"),
         {:ok, asset_urls} <- optional_string_list(arguments, "asset_urls"),
         :ok <- validate_asset_urls(asset_urls) do
      {:ok,
       %{
         issue_id: issue_id,
         comment_id: comment_id,
         body: append_asset_urls(body, asset_urls)
       }}
    end
  end

  defp upsert_comment_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with body plus issue_id or comment_id."}}

  defp prepare_file_upload_args(arguments) when is_map(arguments) do
    with {:ok, filename} <- required_string(arguments, "filename"),
         {:ok, content_type} <- required_string(arguments, "content_type"),
         {:ok, size} <- required_positive_integer(arguments, "size") do
      {:ok,
       %{
         filename: filename,
         content_type: content_type,
         size: size,
         make_public: optional_nullable_boolean(arguments, "make_public")
       }}
    end
  end

  defp prepare_file_upload_args(_arguments), do: {:error, {:invalid_arguments, "Expected an object with filename, content_type, and size."}}

  defp validate_empty_args(nil), do: :ok
  defp validate_empty_args(arguments) when is_map(arguments) and map_size(arguments) == 0, do: :ok
  defp validate_empty_args(_arguments), do: {:error, {:invalid_arguments, "Expected an empty object."}}

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
      nil ->
        nil

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      value when is_atom(value) ->
        value |> Atom.to_string() |> String.trim()

      _value ->
        nil
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

  defp fetch_atom_optional_value(arguments, key) when is_atom(key) do
    if Map.has_key?(arguments, key), do: {:ok, Map.get(arguments, key)}, else: :error
  end

  defp optional_integer(arguments, key, default, min, max) do
    value = optional_value(arguments, key)

    cond do
      is_nil(value) ->
        {:ok, default}

      is_integer(value) and value in min..max ->
        {:ok, value}

      true ->
        {:error, {:invalid_arguments, "#{key} must be an integer between #{min} and #{max}."}}
    end
  end

  defp required_positive_integer(arguments, key) do
    case optional_value(arguments, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "#{key} must be a positive integer."}}
    end
  end

  defp optional_boolean(arguments, key, default) do
    case optional_value(arguments, key) do
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp optional_nullable_boolean(arguments, key) do
    case optional_value(arguments, key) do
      value when is_boolean(value) -> value
      _value -> nil
    end
  end

  defp optional_string_list(arguments, key) do
    case optional_value(arguments, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        values =
          values
          |> Enum.flat_map(fn
            value when is_binary(value) ->
              case String.trim(value) do
                "" -> []
                normalized -> [normalized]
              end

            _value ->
              []
          end)

        {:ok, values}

      _value ->
        {:error, {:invalid_arguments, "#{key} must be an array of strings."}}
    end
  end

  defp camelize(key) do
    [first | rest] = String.split(key, "_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end

  defp atom_key("issue_id"), do: :issue_id
  defp atom_key("include_comments"), do: :include_comments
  defp atom_key("include_attachments"), do: :include_attachments
  defp atom_key("comment_limit"), do: :comment_limit
  defp atom_key("workpad_heading"), do: :workpad_heading
  defp atom_key("state_name"), do: :state_name
  defp atom_key("expected_current_state"), do: :expected_current_state
  defp atom_key("reason"), do: :reason
  defp atom_key("heading"), do: :heading
  defp atom_key("body"), do: :body
  defp atom_key("comment_id"), do: :comment_id
  defp atom_key("match_heading"), do: :match_heading
  defp atom_key("mode"), do: :mode
  defp atom_key("url"), do: :url
  defp atom_key("title"), do: :title
  defp atom_key("repo_provider_kind"), do: :repo_provider_kind
  defp atom_key("repository"), do: :repository
  defp atom_key("change_proposal_id"), do: :change_proposal_id
  defp atom_key("asset_urls"), do: :asset_urls
  defp atom_key("filename"), do: :filename
  defp atom_key("content_type"), do: :content_type
  defp atom_key("size"), do: :size
  defp atom_key("make_public"), do: :make_public
  defp atom_key(_key), do: nil

  defp validate_workpad_mode("replace"), do: :ok
  defp validate_workpad_mode(mode), do: {:error, {:invalid_arguments, "Unsupported workpad mode #{inspect(mode)}."}}

  defp append_asset_urls(body, []), do: body

  defp append_asset_urls(body, asset_urls) do
    [String.trim_trailing(body), "", "Attached assets:" | Enum.map(asset_urls, &("- " <> &1))]
    |> Enum.join("\n")
  end

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" -> :ok
      _uri -> {:error, {:invalid_arguments, "url must be an absolute HTTP(S) URL."}}
    end
  end

  defp validate_asset_urls(asset_urls) do
    Enum.reduce_while(asset_urls, :ok, fn url, :ok ->
      case validate_url(url) do
        :ok -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, {:invalid_arguments, "asset_urls must contain only absolute HTTP(S) URLs."}}}
      end
    end)
  end

  defp response_issue(response) do
    case get_in(response, ["data", "issue"]) do
      issue when is_map(issue) -> {:ok, issue}
      _issue -> {:error, :issue_not_found}
    end
  end

  defp response_viewer(response) do
    case get_in(response, ["data", "viewer"]) do
      viewer when is_map(viewer) -> {:ok, viewer}
      _viewer -> {:error, :viewer_not_found}
    end
  end

  defp mutation_issue(response, path, failure_reason), do: mutation_object(response, path, "issue", failure_reason)
  defp mutation_comment(response, path, failure_reason), do: mutation_object(response, path, "comment", failure_reason)
  defp mutation_attachment(response, path, failure_reason), do: mutation_object(response, path, "attachment", failure_reason)
  defp mutation_upload_file(response, path, failure_reason), do: mutation_object(response, path, "uploadFile", failure_reason)

  defp mutation_object(response, path, object_key, failure_reason) do
    mutation = get_in(response, path)

    cond do
      not is_map(mutation) ->
        {:error, {:provider_unknown_payload, response}}

      Map.get(mutation, "success") != true ->
        {:error, failure_reason}

      is_map(Map.get(mutation, object_key)) ->
        {:ok, Map.fetch!(mutation, object_key)}

      true ->
        {:error, {:provider_unknown_payload, response}}
    end
  end

  defp snapshot_issue(issue, args) do
    %{
      "id" => Map.get(issue, "id"),
      "identifier" => Map.get(issue, "identifier"),
      "title" => Map.get(issue, "title"),
      "description" => Map.get(issue, "description"),
      "branchName" => Map.get(issue, "branchName"),
      "url" => Map.get(issue, "url"),
      "state" => Map.get(issue, "state"),
      "team" => %{"states" => team_states(issue)},
      "labels" => nodes(issue, "labels"),
      "attachments" => if(args.include_attachments, do: nodes(issue, "attachments"), else: []),
      "comments" => if(args.include_comments, do: nodes(issue, "comments"), else: [])
    }
  end

  defp moved_issue(issue, state) do
    %{
      "id" => Map.get(issue, "id"),
      "identifier" => Map.get(issue, "identifier"),
      "state" => state
    }
  end

  defp team_states(issue), do: get_in(issue, ["team", "states", "nodes"]) || []
  defp nodes(parent, key), do: get_in(parent, [key, "nodes"]) || []

  defp canonical_workpad_heading(heading) do
    title = workpad_heading_title(heading)

    if title == "" do
      {:error, {:invalid_arguments, "Workpad heading must contain heading text."}}
    else
      {:ok, "## " <> title}
    end
  end

  defp canonical_workpad_body(canonical_heading, body) do
    body = String.trim_leading(body)

    case String.split(body, "\n", parts: 2) do
      [first_line, rest] ->
        if workpad_heading_line?(first_line, canonical_heading) do
          canonical_heading <> "\n" <> rest
        else
          canonical_heading <> "\n\n" <> body
        end

      [first_line] ->
        if workpad_heading_line?(first_line, canonical_heading) do
          canonical_heading
        else
          canonical_heading <> "\n\n" <> body
        end
    end
  end

  defp workpad_heading_candidates(heading) do
    title = workpad_heading_title(heading)

    [
      "## " <> title,
      title,
      heading
    ]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp workpad_heading_title(heading) when is_binary(heading) do
    heading
    |> String.trim()
    |> String.replace(~r/^#+\s*/, "")
    |> String.trim()
  end

  defp workpad_heading_title(_heading), do: ""

  defp workpad_heading_line?(line, canonical_heading) do
    workpad_heading_title(line) == workpad_heading_title(canonical_heading)
  end

  defp workpad_from_issue(issue, heading_or_headings) do
    headings =
      heading_or_headings
      |> List.wrap()
      |> Enum.flat_map(&workpad_heading_candidates/1)
      |> Enum.uniq()

    comments = issue |> nodes("comments") |> Enum.filter(&active_comment?/1)

    heading_match =
      comments
      |> Enum.filter(fn comment ->
        body = Map.get(comment, "body")
        is_binary(body) and Enum.any?(headings, &String.starts_with?(body, &1))
      end)
      |> latest_comment()

    heading_match || latest_legacy_workpad_comment(comments)
  end

  defp active_comment?(comment) when is_map(comment), do: is_nil(Map.get(comment, "resolvedAt"))
  defp active_comment?(_comment), do: false

  defp latest_comment([]), do: nil
  defp latest_comment(comments), do: Enum.max_by(comments, &comment_sort_key/1)

  defp comment_sort_key(comment), do: Map.get(comment, "updatedAt") || Map.get(comment, "createdAt") || ""

  defp latest_legacy_workpad_comment(comments) do
    comments
    |> Enum.filter(fn comment ->
      body = Map.get(comment, "body")

      is_binary(body) and
        String.contains?(body, "### Plan") and
        String.contains?(body, "### Acceptance Criteria") and
        String.contains?(body, "### Validation")
    end)
    |> latest_comment()
  end

  defp expected_current_state(_issue, nil), do: :ok

  defp expected_current_state(issue, expected) do
    if get_in(issue, ["state", "name"]) == expected do
      :ok
    else
      {:error, {:conflict, "Issue state changed before move.", %{expected: expected, actual: get_in(issue, ["state", "name"])}}}
    end
  end

  defp resolve_state(issue, state_name) do
    matches = Enum.filter(team_states(issue), &(Map.get(&1, "name") == state_name))

    case matches do
      [state] -> {:ok, state}
      [] -> {:error, {:state_not_found, state_name}}
      _states -> {:error, {:ambiguous_state, state_name}}
    end
  end

  defp existing_attachment(issue, url) do
    canonical = canonical_url(url)

    issue
    |> nodes("attachments")
    |> Enum.find(&(canonical_url(Map.get(&1, "url")) == canonical))
  end

  defp github_pr_url?(url) do
    case URI.parse(url) do
      %URI{host: "github.com", path: path} when is_binary(path) -> String.contains?(path, "/pull/")
      _uri -> false
    end
  end

  defp canonical_url(url) when is_binary(url), do: String.trim(url)
  defp canonical_url(_url), do: nil

  defp success_payload(data), do: %{"data" => data, "warnings" => []}

  defp typed_failure(reason) do
    {code, message, details} = typed_error(reason)
    {:failure, %{"error" => %{"code" => code, "message" => message, "details" => details}}}
  end

  defp typed_error({:invalid_arguments, message}), do: {"invalid_arguments", message, %{}}
  defp typed_error(:issue_not_found), do: {"not_found", "Linear issue was not found.", %{}}
  defp typed_error(:viewer_not_found), do: {"not_found", "Linear viewer was not returned.", %{}}
  defp typed_error({:state_not_found, state_name}), do: {"state_not_found", "The issue's team does not contain the requested state.", %{"stateName" => state_name}}
  defp typed_error({:ambiguous_state, state_name}), do: {"ambiguous_state", "The issue's team contains multiple states with the requested name.", %{"stateName" => state_name}}
  defp typed_error({:conflict, message, details}) when is_map(details), do: {"conflict", message, details}
  defp typed_error(:issue_update_failed), do: {"provider_request_failed", "Linear issue state update did not report success.", %{}}
  defp typed_error(:comment_update_failed), do: {"provider_request_failed", "Linear comment update did not report success.", %{}}
  defp typed_error(:comment_create_failed), do: {"provider_request_failed", "Linear comment create did not report success.", %{}}
  defp typed_error(:attachment_create_failed), do: {"provider_request_failed", "Linear attachment create did not report success.", %{}}
  defp typed_error(:file_upload_failed), do: {"provider_request_failed", "Linear file upload preparation did not report success.", %{}}
  defp typed_error(:missing_linear_api_token), do: {"missing_auth", "Symphony is missing Linear auth.", %{}}
  defp typed_error({:provider_validation_failed, response}), do: {"provider_validation_failed", "Linear rejected the typed workflow tool request.", %{"response" => response}}
  defp typed_error({:provider_unknown_payload, payload}), do: {"provider_request_failed", "Linear returned an unexpected response shape.", %{"payload" => inspect(payload)}}
  defp typed_error({:linear_api_request, reason}), do: {"provider_request_failed", "Linear request failed before receiving a successful response.", %{"reason" => inspect(reason)}}
  defp typed_error({:linear_api_status, status}), do: {"provider_request_failed", "Linear request failed with an HTTP error.", %{"status" => status}}
  defp typed_error(reason), do: {"provider_request_failed", "Linear typed workflow tool execution failed.", %{"reason" => inspect(reason)}}
end
