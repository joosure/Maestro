defmodule SymphonyElixir.RepoProvider.ToolExecutor do
  @moduledoc """
  Executes repo-provider typed workflow tools through the RepoProvider facade.
  """

  alias SymphonyElixir.Agent.DynamicTool.Serializer
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.ChangeProposalBody
  alias SymphonyElixir.RepoProvider.Error

  @schema_version "1"
  @risk_flags ["external_network", "secret_access", "external_process", "privileged_api"]

  @snapshot_tool "repo_change_proposal_snapshot"
  @create_or_update_tool "repo_create_or_update_change_proposal"
  @discussion_tool "repo_read_change_proposal_discussion"
  @add_comment_tool "repo_add_change_proposal_comment"
  @submit_review_tool "repo_submit_change_proposal_review"
  @reply_review_comment_tool "repo_reply_change_proposal_review_comment"
  @checks_tool "repo_read_change_proposal_checks"
  @merge_tool "repo_merge_change_proposal"
  @close_tool "repo_close_change_proposal"

  @snapshot_capability "repo.change_proposal_snapshot"
  @create_or_update_capability "repo.create_or_update_change_proposal"
  @discussion_capability "repo.read_change_proposal_discussion"
  @add_comment_capability "repo.add_change_proposal_comment"
  @submit_review_capability "repo.submit_change_proposal_review"
  @reply_review_comment_capability "repo.reply_change_proposal_review_comment"
  @checks_capability "repo.read_change_proposal_checks"
  @merge_capability "repo.merge_change_proposal"
  @close_capability "repo.close_change_proposal"

  @tool_requirements %{
    @snapshot_tool => [:pr_view],
    @create_or_update_tool => [:pr_view, :pr_create, :pr_edit],
    @discussion_tool => [:pr_issue_comments, :pr_reviews, :pr_review_comments],
    @add_comment_tool => [:pr_add_issue_comment],
    @submit_review_tool => [:pr_submit_review],
    @reply_review_comment_tool => [:pr_reply_review_comment],
    @checks_tool => [:pr_checks],
    @merge_tool => [:pr_merge],
    @close_tool => [:pr_close]
  }

  @spec tool_specs(map()) :: [map()]
  def tool_specs(repo) when is_map(repo) do
    supported = MapSet.new(RepoProvider.capabilities(repo))

    [
      snapshot_spec(repo),
      create_or_update_spec(repo),
      discussion_spec(repo),
      add_comment_spec(repo),
      submit_review_spec(repo),
      reply_review_comment_spec(repo),
      checks_spec(repo),
      merge_spec(repo),
      close_spec(repo)
    ]
    |> Enum.filter(&requirements_satisfied?(&1, supported))
  end

  def tool_specs(_repo), do: []

  @spec supported_tool_names(map()) :: [String.t()]
  def supported_tool_names(repo) when is_map(repo),
    do: Enum.map(tool_specs(repo), &Map.fetch!(&1, "name"))

  def supported_tool_names(_repo), do: []

  @spec execute(map(), String.t() | nil, term(), keyword()) ::
          SymphonyElixir.Agent.DynamicTool.Source.tool_result()
  def execute(repo, tool, arguments, opts)

  def execute(repo, @snapshot_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @snapshot_tool),
      do: change_proposal_snapshot(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @create_or_update_tool, arguments, opts)
      when is_map(repo) and is_list(opts) do
    if supported?(repo, @create_or_update_tool),
      do: create_or_update_change_proposal(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @discussion_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @discussion_tool),
      do: read_change_proposal_discussion(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @add_comment_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @add_comment_tool),
      do: add_change_proposal_comment(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @submit_review_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @submit_review_tool),
      do: submit_change_proposal_review(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @reply_review_comment_tool, arguments, opts)
      when is_map(repo) and is_list(opts) do
    if supported?(repo, @reply_review_comment_tool),
      do: reply_change_proposal_review_comment(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @checks_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @checks_tool),
      do: read_change_proposal_checks(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @merge_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @merge_tool),
      do: merge_change_proposal(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, @close_tool, arguments, opts) when is_map(repo) and is_list(opts) do
    if supported?(repo, @close_tool),
      do: close_change_proposal(repo, arguments, opts),
      else: unsupported_tool(repo)
  end

  def execute(repo, _tool, _arguments, _opts) when is_map(repo), do: unsupported_tool(repo)

  def execute(_repo, _tool, _arguments, _opts),
    do: {:error, :repo_provider_dynamic_tool_context_unavailable}

  defp snapshot_spec(repo) do
    tool_spec(
      repo,
      @snapshot_tool,
      @snapshot_capability,
      "Read a repository change proposal snapshot, optionally including discussion and check summaries.",
      "read_only",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          },
          "include_discussion" => %{
            "type" => "boolean",
            "description" => "Whether to include comments and reviews."
          },
          "include_checks" => %{
            "type" => "boolean",
            "description" => "Whether to include provider check runs."
          }
        }
      }
    )
  end

  defp create_or_update_spec(repo) do
    tool_spec(
      repo,
      @create_or_update_tool,
      @create_or_update_capability,
      "Create or update a repository change proposal without requiring the agent to call provider-native PR commands. To create a new proposal, call with mode \"create\" plus title, base, and head. Create is idempotent by head branch: if a proposal already exists for the head, Symphony updates it instead of creating a duplicate. If body is provided it must be one JSON string; omit body to let Symphony generate the configured deterministic default.",
      "write",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "mode" => %{
            "type" => ["string", "null"],
            "enum" => ["upsert", "create", "update", nil],
            "description" => "Operation mode. Defaults to upsert."
          },
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Existing change proposal number or target for update."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Existing change proposal URL for update."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Existing branch target for update when supported."
          },
          "title" => %{
            "type" => ["string", "null"],
            "description" => "Change proposal title. Required when mode is create."
          },
          "body" => %{
            "type" => ["string", "null"],
            "description" => "Optional change proposal body as one JSON string. Do not split body sections into extra fields; omit it to use Symphony's configured deterministic default."
          },
          "base" => %{
            "type" => ["string", "null"],
            "description" => "Destination/base branch. Required when mode is create."
          },
          "head" => %{
            "type" => ["string", "null"],
            "description" => "Source/head branch for create. Required when mode is create."
          },
          "labels" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Labels to apply after create or update when supported."
          }
        }
      }
    )
  end

  defp discussion_spec(repo) do
    tool_spec(
      repo,
      @discussion_tool,
      @discussion_capability,
      "Read top-level comments, review summaries, and inline review comments for a repository change proposal.",
      "read_only",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          },
          "include_issue_comments" => %{
            "type" => "boolean",
            "description" => "Whether to read top-level comments."
          },
          "include_reviews" => %{
            "type" => "boolean",
            "description" => "Whether to read review summaries."
          },
          "include_review_comments" => %{
            "type" => "boolean",
            "description" => "Whether to read inline review comments."
          }
        }
      }
    )
  end

  defp add_comment_spec(repo) do
    tool_spec(
      repo,
      @add_comment_tool,
      @add_comment_capability,
      "Post a top-level comment on a repository change proposal through the configured repo provider.",
      "write",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["body"],
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          },
          "reply_to_comment_id" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Optional top-level feedback comment id this response addresses."
          },
          "body" => %{"type" => "string", "description" => "Comment body as one string."}
        }
      }
    )
  end

  defp reply_review_comment_spec(repo) do
    tool_spec(
      repo,
      @reply_review_comment_tool,
      @reply_review_comment_capability,
      "Reply to an inline review comment on a repository change proposal through the configured repo provider.",
      "write",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["comment_id", "body"],
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          },
          "comment_id" => %{
            "type" => ["string", "integer"],
            "description" => "Provider review comment id to reply to."
          },
          "body" => %{"type" => "string", "description" => "Reply body as one string."}
        }
      }
    )
  end

  defp submit_review_spec(repo) do
    tool_spec(
      repo,
      @submit_review_tool,
      @submit_review_capability,
      "Submit a provider review on a repository change proposal, including a comment, approval, or change request, without exposing provider-native review event names.",
      "write",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["event", "body"],
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          },
          "event" => %{
            "type" => "string",
            "enum" => ["comment", "approve", "request_changes"],
            "description" => "Provider-neutral review decision."
          },
          "body" => %{"type" => "string", "description" => "Review body as one string."}
        }
      }
    )
  end

  defp checks_spec(repo) do
    tool_spec(
      repo,
      @checks_tool,
      @checks_capability,
      "Read check runs for a repository change proposal through the configured repo provider.",
      "read_only",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer", "null"],
            "description" => "Provider change proposal number or target."
          },
          "url" => %{
            "type" => ["string", "null"],
            "description" => "Provider change proposal URL."
          },
          "branch" => %{
            "type" => ["string", "null"],
            "description" => "Provider branch target when supported."
          }
        }
      }
    )
  end

  defp merge_spec(repo) do
    tool_spec(
      repo,
      @merge_tool,
      @merge_capability,
      "Merge a repository change proposal through the configured repo provider.",
      "destructive",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["number"],
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer"],
            "description" => "Provider change proposal number or target."
          },
          "merge_style" => %{
            "type" => ["string", "null"],
            "enum" => ["merge", "squash", "rebase", nil],
            "description" => "Merge style when supported."
          },
          "subject" => %{
            "type" => ["string", "null"],
            "description" => "Merge commit subject when supported."
          },
          "body" => %{
            "type" => ["string", "null"],
            "description" => "Merge commit body when supported."
          }
        }
      }
    )
  end

  defp close_spec(repo) do
    tool_spec(
      repo,
      @close_tool,
      @close_capability,
      "Close a repository change proposal through the configured repo provider.",
      "destructive",
      %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["number"],
        "properties" => %{
          "number" => %{
            "type" => ["string", "integer"],
            "description" => "Provider change proposal number or target."
          },
          "comment" => %{
            "type" => ["string", "null"],
            "description" => "Optional close comment when supported."
          }
        }
      }
    )
  end

  defp tool_spec(repo, name, capability, description, side_effect, input_schema) do
    %{
      "name" => name,
      "description" => description,
      "inputSchema" => input_schema,
      "schemaVersion" => @schema_version,
      "sideEffect" => side_effect,
      "riskFlags" => @risk_flags,
      "workflowCapability" => capability,
      "sourceKind" => RepoProvider.current_kind(repo)
    }
  end

  defp requirements_satisfied?(%{"name" => name}, supported) do
    name
    |> requirements()
    |> Enum.all?(&MapSet.member?(supported, &1))
  end

  defp supported?(repo, tool) do
    supported = MapSet.new(RepoProvider.capabilities(repo))
    Enum.all?(requirements(tool), &MapSet.member?(supported, &1))
  end

  defp requirements(tool), do: Map.get(@tool_requirements, tool, [])

  defp change_proposal_snapshot(repo, arguments, opts) do
    with {:ok, args} <- snapshot_args(arguments),
         {:ok, snapshot} <- read_change_proposal_snapshot(repo, args, opts) do
      {:success, success_payload(snapshot, snapshot_warnings(snapshot))}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp create_or_update_change_proposal(repo, arguments, opts) do
    case create_or_update_args(arguments) do
      {:ok, %{mode: "create"} = args} -> create_change_proposal(repo, args, opts)
      {:ok, %{mode: "update"} = args} -> update_existing_change_proposal(repo, args, opts)
      {:ok, %{mode: "upsert"} = args} -> upsert_change_proposal(repo, args, opts)
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp read_change_proposal_discussion(repo, arguments, opts) do
    with {:ok, args} <- discussion_args(arguments),
         {:ok, discussion} <- read_discussion(repo, args, opts) do
      {:success, success_payload(%{"discussion" => discussion})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp add_change_proposal_comment(repo, arguments, opts) do
    with {:ok, args} <- comment_args(arguments),
         {:ok, args} <- canonicalize_top_level_response_target(repo, args, opts),
         {:ok, comment} <-
           RepoProvider.pr_add_issue_comment(
             repo,
             args
             |> Map.update!(:body, &body_with_top_level_response_marker(&1, Map.get(args, :reply_to_comment_id)))
             |> provider_opts(opts, [:number, :body])
           ) do
      {:success, success_payload(%{"action" => "comment_added", "comment" => comment})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp canonicalize_top_level_response_target(repo, %{reply_to_comment_id: reply_to_comment_id} = args, opts)
       when is_binary(reply_to_comment_id) do
    case RepoProvider.pr_issue_comments(repo, provider_opts(args, opts, [:number])) do
      {:ok, comments} when is_list(comments) ->
        {:ok, Map.put(args, :reply_to_comment_id, canonical_top_level_comment_id(comments, reply_to_comment_id))}

      _other ->
        {:ok, args}
    end
  end

  defp canonicalize_top_level_response_target(_repo, args, _opts), do: {:ok, args}

  defp reply_change_proposal_review_comment(repo, arguments, opts) do
    with {:ok, args} <- review_reply_args(arguments),
         {:ok, comment} <-
           RepoProvider.pr_reply_review_comment(
             repo,
             provider_opts(args, opts, [:number, :comment_id, :body])
           ) do
      {:success, success_payload(%{"action" => "review_comment_replied", "comment" => comment})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp submit_change_proposal_review(repo, arguments, opts) do
    with {:ok, args} <- review_args(arguments),
         {:ok, review} <-
           RepoProvider.pr_submit_review(
             repo,
             provider_opts(args, opts, [:number, :event, :body])
           ) do
      {:success, success_payload(%{"action" => "review_submitted", "review" => review})}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp read_change_proposal_checks(repo, arguments, opts) do
    with {:ok, args} <- target_args(arguments),
         {:ok, checks} <- read_checks(repo, args, opts) do
      {:success, success_payload(%{"checks" => checks}, checks_warnings(checks))}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp merge_change_proposal(repo, arguments, opts) do
    with {:ok, args} <- merge_args(arguments),
         {:ok, url} <-
           RepoProvider.pr_merge(
             repo,
             provider_opts(args, opts, [:number, :merge_style, :subject, :body])
           ) do
      {:success,
       success_payload(%{
         "changeProposal" => %{"target" => args.number, "url" => url, "state" => "merged"},
         "action" => "merged"
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp close_change_proposal(repo, arguments, opts) do
    with {:ok, args} <- close_args(arguments),
         {:ok, url} <- RepoProvider.pr_close(repo, provider_opts(args, opts, [:number, :comment])) do
      {:success,
       success_payload(%{
         "changeProposal" => %{"target" => args.number, "url" => url, "state" => "closed"},
         "action" => "closed"
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp upsert_change_proposal(repo, args, opts) do
    if target(args) do
      update_existing_change_proposal(repo, args, opts)
    else
      case view_change_proposal(repo, args, opts) do
        {:ok, _proposal} -> update_existing_change_proposal(repo, args, opts)
        {:error, %Error{} = error} -> maybe_create_after_missing_view(repo, args, opts, error)
        {:error, reason} -> typed_failure(reason)
      end
    end
  end

  defp maybe_create_after_missing_view(repo, args, opts, %Error{code: code})
       when code in [:github_pr_not_found, :cnb_pull_not_found, :memory_pr_not_configured] do
    create_change_proposal(repo, args, opts)
  end

  defp maybe_create_after_missing_view(_repo, _args, _opts, error), do: typed_failure(error)

  defp update_existing_change_proposal(repo, args, opts) do
    target = target(args)

    with {:ok, proposal} <- edit_or_read_existing(repo, args, opts),
         {:ok, labels} <- apply_labels(repo, target, args.labels, opts) do
      {:success,
       success_payload(%{
         "changeProposal" => proposal,
         "action" => "updated",
         "labels" => labels
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp edit_or_read_existing(repo, args, opts) do
    if editable_change_proposal?(args) do
      edit_opts = provider_opts(args, opts, [:number, :title, :body, :base])

      with {:ok, url} <- RepoProvider.pr_edit(repo, edit_opts) do
        view_or_minimal(repo, args, opts, %{"target" => args.number, "url" => url})
      end
    else
      view_change_proposal(repo, args, opts)
    end
  end

  defp create_change_proposal(repo, args, opts) do
    with :ok <- require_create_fields(args),
         {:ok, args} <- ensure_create_body(repo, args) do
      case view_existing_change_proposal_for_create(repo, args, opts) do
        {:ok, _proposal} ->
          update_existing_change_proposal(
            repo,
            Map.merge(args, %{number: args.head, branch: args.head}),
            opts
          )

        {:error, %Error{} = error} ->
          if missing_change_proposal?(error) do
            do_create_change_proposal(repo, args, opts)
          else
            typed_failure(error)
          end

        {:error, reason} ->
          typed_failure(reason)
      end
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp do_create_change_proposal(repo, args, opts) do
    with {:ok, url} <-
           RepoProvider.pr_create(repo, provider_opts(args, opts, [:title, :body, :base, :head])),
         {:ok, labels} <- apply_labels(repo, url, args.labels, opts),
         {:ok, proposal} <-
           view_or_minimal(repo, Map.put(args, :number, url), opts, %{"url" => url}) do
      {:success,
       success_payload(%{
         "changeProposal" => proposal,
         "action" => "created",
         "labels" => labels
       })}
    else
      {:error, reason} -> typed_failure(reason)
    end
  end

  defp view_existing_change_proposal_for_create(repo, %{head: head} = args, opts)
       when is_binary(head) and head != "" do
    view_change_proposal(repo, Map.merge(args, %{number: head, branch: head}), opts)
  end

  defp view_existing_change_proposal_for_create(_repo, _args, _opts),
    do: {:error, {:invalid_arguments, "Creating a change proposal requires head."}}

  defp view_or_minimal(repo, args, opts, fallback) do
    case view_change_proposal(repo, args, opts) do
      {:ok, proposal} -> {:ok, proposal}
      {:error, _reason} -> {:ok, fallback}
    end
  end

  defp view_change_proposal(repo, args, opts) do
    RepoProvider.pr_view(repo, provider_opts(args, opts, [:number]))
  end

  defp read_change_proposal_snapshot(repo, args, opts) do
    case view_change_proposal(repo, args, opts) do
      {:ok, proposal} ->
        with {:ok, discussion} <- maybe_read_discussion(repo, args, opts),
             {:ok, checks} <- maybe_read_checks(repo, args, opts) do
          {:ok,
           %{
             "exists" => true,
             "changeProposal" => proposal,
             "discussion" => discussion,
             "checks" => checks
           }}
        end

      {:error, %Error{} = error} ->
        if missing_change_proposal?(error) do
          {:ok, missing_change_proposal_snapshot(repo, args)}
        else
          {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp missing_change_proposal?(%Error{code: code})
       when code in [:github_pr_not_found, :cnb_pull_not_found, :memory_pr_not_configured],
       do: true

  defp missing_change_proposal?(_error), do: false

  defp missing_change_proposal_snapshot(repo, args) do
    %{
      "exists" => false,
      "changeProposal" => nil,
      "lookup" => %{
        "provider" => RepoProvider.current_kind(repo),
        "selector" => change_proposal_selector(args)
      },
      "discussion" => nil,
      "checks" => nil
    }
  end

  defp change_proposal_selector(%{url: url}) when is_binary(url) and url != "",
    do: %{"kind" => "url", "value" => url}

  defp change_proposal_selector(%{branch: branch}) when is_binary(branch) and branch != "",
    do: %{"kind" => "branch", "value" => branch}

  defp change_proposal_selector(%{number: number}) when is_binary(number) and number != "",
    do: %{"kind" => "number", "value" => number}

  defp change_proposal_selector(_args), do: %{"kind" => "current_branch", "value" => nil}

  defp maybe_read_discussion(repo, %{include_discussion: true} = args, opts),
    do: read_discussion(repo, args, opts)

  defp maybe_read_discussion(_repo, _args, _opts), do: {:ok, nil}

  defp maybe_read_checks(repo, %{include_checks: true} = args, opts),
    do: read_checks(repo, args, opts)

  defp maybe_read_checks(_repo, _args, _opts), do: {:ok, nil}

  defp read_discussion(repo, args, opts) do
    with {:ok, issue_comments} <-
           maybe_provider_call(args.include_issue_comments, fn ->
             RepoProvider.pr_issue_comments(repo, provider_opts(args, opts, [:number]))
           end),
         {:ok, reviews} <-
           maybe_provider_call(args.include_reviews, fn ->
             RepoProvider.pr_reviews(repo, provider_opts(args, opts, [:number]))
           end),
         {:ok, review_comments} <-
           maybe_provider_call(args.include_review_comments, fn ->
             RepoProvider.pr_review_comments(repo, provider_opts(args, opts, [:number]))
           end) do
      actionable_items = actionable_items(repo, args, issue_comments, reviews, review_comments)

      {:ok,
       %{
         "issueComments" => issue_comments,
         "reviews" => reviews,
         "reviewComments" => review_comments,
         "reviewThreads" => review_threads(repo, args, review_comments),
         "feedbackActionPolicy" => feedback_action_policy(repo, args),
         "actionableItems" => actionable_items,
         "unresolvedFeedbackSummary" => unresolved_feedback_summary(actionable_items),
         "summary" => discussion_summary(issue_comments, reviews, review_comments, actionable_items)
       }}
    end
  end

  defp read_checks(repo, args, opts) do
    with {:ok, checks} <- RepoProvider.pr_checks(repo, provider_opts(args, opts, [:number])) do
      {:ok,
       %{
         "runs" => checks,
         "summary" => check_summary(checks)
       }}
    end
  end

  defp maybe_provider_call(true, fun), do: fun.()
  defp maybe_provider_call(false, _fun), do: {:ok, []}

  defp apply_labels(repo, target, labels, opts) when is_list(labels) do
    if RepoProvider.supports?(repo, :pr_add_label) do
      Enum.reduce_while(labels, {:ok, []}, fn label, {:ok, acc} ->
        case RepoProvider.pr_add_label(repo, Keyword.merge(opts, number: target, label: label)) do
          {:ok, url} -> {:cont, {:ok, [%{"label" => label, "url" => url} | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, applied} -> {:ok, Enum.reverse(applied)}
        {:error, _reason} = error -> error
      end
    else
      {:ok, []}
    end
  end

  defp snapshot_args(arguments) when is_map(arguments) do
    with :ok <-
           validate_allowed_fields(arguments, [
             "number",
             "url",
             "branch",
             "include_discussion",
             "include_checks"
           ]),
         {:ok, args} <- target_args(arguments) do
      {:ok,
       args
       |> Map.put(:include_discussion, optional_boolean(arguments, "include_discussion", false))
       |> Map.put(:include_checks, optional_boolean(arguments, "include_checks", false))
       |> Map.put(:include_issue_comments, true)
       |> Map.put(:include_reviews, true)
       |> Map.put(:include_review_comments, true)}
    end
  end

  defp snapshot_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for change proposal snapshot."}}

  defp create_or_update_args(arguments) when is_map(arguments) do
    with :ok <-
           validate_allowed_fields(arguments, [
             "mode",
             "number",
             "url",
             "branch",
             "title",
             "body",
             "base",
             "head",
             "labels"
           ]),
         {:ok, args} <- target_args(arguments),
         {:ok, mode} <- mode(arguments),
         {:ok, labels} <- optional_string_list(arguments, "labels") do
      {:ok,
       args
       |> Map.merge(%{
         mode: mode,
         title: nullable_string(arguments, "title"),
         body: nullable_string(arguments, "body"),
         base: nullable_string(arguments, "base"),
         head: nullable_string(arguments, "head"),
         labels: labels
       })}
    end
  end

  defp create_or_update_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for change proposal create/update."}}

  defp discussion_args(arguments) when is_map(arguments) do
    with :ok <-
           validate_allowed_fields(arguments, [
             "number",
             "url",
             "branch",
             "include_issue_comments",
             "include_reviews",
             "include_review_comments"
           ]),
         {:ok, args} <- target_args(arguments) do
      {:ok,
       args
       |> Map.put(
         :include_issue_comments,
         optional_boolean(arguments, "include_issue_comments", true)
       )
       |> Map.put(:include_reviews, optional_boolean(arguments, "include_reviews", true))
       |> Map.put(
         :include_review_comments,
         optional_boolean(arguments, "include_review_comments", true)
       )}
    end
  end

  defp discussion_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for change proposal discussion."}}

  defp comment_args(arguments) when is_map(arguments) do
    with :ok <- validate_allowed_fields(arguments, ["number", "url", "branch", "body", "reply_to_comment_id"]),
         {:ok, args} <- target_args(arguments),
         {:ok, body} <- required_string(arguments, "body") do
      {:ok,
       args
       |> Map.put(:body, body)
       |> put_optional(:reply_to_comment_id, optional_id(arguments, "reply_to_comment_id"))}
    end
  end

  defp comment_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for change proposal comment."}}

  defp review_reply_args(arguments) when is_map(arguments) do
    with :ok <-
           validate_allowed_fields(arguments, ["number", "url", "branch", "comment_id", "body"]),
         {:ok, args} <- target_args(arguments),
         {:ok, comment_id} <- required_string(arguments, "comment_id"),
         {:ok, body} <- required_string(arguments, "body") do
      {:ok, args |> Map.put(:comment_id, comment_id) |> Map.put(:body, body)}
    end
  end

  defp review_reply_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for review comment reply."}}

  defp review_args(arguments) when is_map(arguments) do
    with :ok <- validate_allowed_fields(arguments, ["number", "url", "branch", "event", "body"]),
         {:ok, args} <- target_args(arguments),
         {:ok, event} <- review_event(arguments),
         {:ok, body} <- required_string(arguments, "body") do
      {:ok, args |> Map.put(:event, event) |> Map.put(:body, body)}
    end
  end

  defp review_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object for change proposal review."}}

  defp target_args(arguments) when is_map(arguments) do
    number =
      nullable_string(arguments, "number") ||
        nullable_string(arguments, "url") ||
        nullable_string(arguments, "branch")

    {:ok,
     %{
       number: number,
       url: nullable_string(arguments, "url"),
       branch: nullable_string(arguments, "branch")
     }}
  end

  defp target_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with an optional change proposal target."}}

  defp merge_args(arguments) when is_map(arguments) do
    with :ok <- validate_allowed_fields(arguments, ["number", "merge_style", "subject", "body"]),
         {:ok, number} <- required_string(arguments, "number"),
         {:ok, merge_style} <- merge_style(arguments) do
      {:ok,
       %{
         number: number,
         merge_style: merge_style,
         subject: nullable_string(arguments, "subject"),
         body: nullable_string(arguments, "body")
       }}
    end
  end

  defp merge_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with number for merge."}}

  defp close_args(arguments) when is_map(arguments) do
    with :ok <- validate_allowed_fields(arguments, ["number", "comment"]),
         {:ok, number} <- required_string(arguments, "number") do
      {:ok, %{number: number, comment: nullable_string(arguments, "comment")}}
    end
  end

  defp close_args(_arguments),
    do: {:error, {:invalid_arguments, "Expected an object with number for close."}}

  defp mode(arguments) do
    case nullable_string(arguments, "mode") || "upsert" do
      mode when mode in ["upsert", "create", "update"] -> {:ok, mode}
      mode -> {:error, {:invalid_arguments, "Unsupported change proposal mode #{inspect(mode)}."}}
    end
  end

  defp merge_style(arguments) do
    case nullable_string(arguments, "merge_style") || "merge" do
      style when style in ["merge", "squash", "rebase"] -> {:ok, style}
      style -> {:error, {:invalid_arguments, "Unsupported merge style #{inspect(style)}."}}
    end
  end

  defp review_event(arguments) do
    case nullable_string(arguments, "event") do
      event when is_binary(event) ->
        event
        |> String.downcase()
        |> String.replace(~r/[\s-]+/, "_")
        |> case do
          normalized when normalized in ["comment", "approve", "request_changes"] ->
            {:ok, normalized}

          normalized ->
            {:error, {:invalid_arguments, "Unsupported review event #{inspect(normalized)}. Use comment, approve, or request_changes."}}
        end

      event ->
        {:error, {:invalid_arguments, "Unsupported review event #{inspect(event)}. Use comment, approve, or request_changes."}}
    end
  end

  defp require_create_fields(args) do
    cond do
      blank?(args.title) ->
        {:error, {:invalid_arguments, "Creating a change proposal requires title."}}

      blank?(args.base) ->
        {:error, {:invalid_arguments, "Creating a change proposal requires base."}}

      blank?(args.head) ->
        {:error, {:invalid_arguments, "Creating a change proposal requires head."}}

      true ->
        :ok
    end
  end

  defp ensure_create_body(_repo, %{body: body} = args) when is_binary(body) and body != "",
    do: {:ok, args}

  defp ensure_create_body(repo, args) do
    with {:ok, body} <- ChangeProposalBody.generate(repo, args) do
      {:ok, Map.put(args, :body, body)}
    end
  end

  defp editable_change_proposal?(args) do
    Enum.any?([args.title, args.body, args.base], &(is_binary(&1) and &1 != ""))
  end

  defp provider_opts(args, opts, fields) do
    Enum.reduce(fields, opts, fn field, acc ->
      case Map.get(args, field) do
        value when is_binary(value) and value != "" -> Keyword.put(acc, field, value)
        value when is_integer(value) -> Keyword.put(acc, field, Integer.to_string(value))
        _value -> acc
      end
    end)
  end

  defp target(%{number: number}) when is_binary(number) and number != "", do: number
  defp target(%{url: url}) when is_binary(url) and url != "", do: url
  defp target(%{branch: branch}) when is_binary(branch) and branch != "", do: branch
  defp target(_args), do: nil

  defp required_string(arguments, key) do
    case nullable_string(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_arguments, "Missing required string field #{key}."}}
    end
  end

  defp nullable_string(arguments, key) do
    arguments
    |> optional_value(key)
    |> case do
      nil -> nil
      value when is_binary(value) -> trim_string(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> trim_string()
      _value -> nil
    end
  end

  defp optional_boolean(arguments, key, default) do
    case optional_value(arguments, key) do
      value when is_boolean(value) -> value
      _value -> default
    end
  end

  defp optional_string_list(arguments, key) do
    case optional_value(arguments, key) do
      nil ->
        {:ok, []}

      values when is_list(values) ->
        {:ok,
         values
         |> Enum.flat_map(fn value ->
           case trim_string(value) do
             nil -> []
             normalized -> [normalized]
           end
         end)
         |> Enum.uniq()}

      _value ->
        {:error, {:invalid_arguments, "#{key} must be a list of strings."}}
    end
  end

  defp optional_id(arguments, key) do
    arguments
    |> optional_value(key)
    |> normalized_id()
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp validate_allowed_fields(arguments, allowed_fields)
       when is_map(arguments) and is_list(allowed_fields) do
    allowed = MapSet.new(allowed_fields)
    allowed_camel = MapSet.new(Enum.map(allowed_fields, &camelize/1))
    allowed_atoms = MapSet.new(Enum.map(allowed_fields, &atom_key/1))

    unexpected =
      arguments
      |> Map.keys()
      |> Enum.reject(&allowed_field?(&1, allowed, allowed_camel, allowed_atoms))
      |> Enum.map(&inspect/1)
      |> Enum.sort()

    case unexpected do
      [] ->
        :ok

      fields ->
        {:error, {:invalid_arguments, "Unsupported argument field(s): #{Enum.join(fields, ", ")}."}}
    end
  end

  defp allowed_field?(key, allowed, allowed_camel, _allowed_atoms) when is_binary(key) do
    MapSet.member?(allowed, key) or MapSet.member?(allowed_camel, key)
  end

  defp allowed_field?(key, _allowed, _allowed_camel, allowed_atoms) when is_atom(key) do
    MapSet.member?(allowed_atoms, key)
  end

  defp allowed_field?(_key, _allowed, _allowed_camel, _allowed_atoms), do: false

  defp optional_value(arguments, key) do
    arguments
    |> fetch_optional_value(key)
    |> fallback_optional_value(arguments, camelize(key))
    |> fallback_optional_value(arguments, atom_key(key))
    |> case do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fallback_optional_value({:ok, _value} = result, _arguments, _key), do: result
  defp fallback_optional_value(:error, arguments, key), do: fetch_optional_value(arguments, key)

  defp fetch_optional_value(_arguments, nil), do: :error
  defp fetch_optional_value(arguments, key), do: Map.fetch(arguments, key)

  defp trim_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_string(_value), do: nil

  defp camelize(key) do
    [first | rest] = String.split(key, "_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end

  defp atom_key("number"), do: :number
  defp atom_key("url"), do: :url
  defp atom_key("branch"), do: :branch
  defp atom_key("include_discussion"), do: :include_discussion
  defp atom_key("include_checks"), do: :include_checks
  defp atom_key("include_issue_comments"), do: :include_issue_comments
  defp atom_key("include_reviews"), do: :include_reviews
  defp atom_key("include_review_comments"), do: :include_review_comments
  defp atom_key("mode"), do: :mode
  defp atom_key("title"), do: :title
  defp atom_key("body"), do: :body
  defp atom_key("base"), do: :base
  defp atom_key("head"), do: :head
  defp atom_key("labels"), do: :labels
  defp atom_key("event"), do: :event
  defp atom_key("comment_id"), do: :comment_id
  defp atom_key("reply_to_comment_id"), do: :reply_to_comment_id
  defp atom_key("merge_style"), do: :merge_style
  defp atom_key("subject"), do: :subject
  defp atom_key("comment"), do: :comment
  defp atom_key(_key), do: nil

  defp check_summary(checks) when is_list(checks) do
    checks
    |> Enum.reduce(%{}, fn check, acc ->
      bucket =
        Map.get(check, "bucket") || Map.get(check, :bucket) || Map.get(check, "state") ||
          Map.get(check, :state) || "unknown"

      Map.update(acc, to_string(bucket), 1, &(&1 + 1))
    end)
  end

  defp discussion_summary(issue_comments, reviews, review_comments, actionable_items) do
    review_state_counts = review_state_counts(reviews)
    change_request_count = Map.get(review_state_counts, "changes_requested", 0)
    review_thread_count = review_thread_count(review_comments)
    review_reply_count = review_reply_count(review_comments)
    unreplied_review_thread_count = unreplied_review_thread_count(review_comments)
    top_level_comment_count = length(issue_comments)
    actionable_feedback_count = length(actionable_items)
    actionable_top_level_comment_count = Enum.count(actionable_items, &(Map.get(&1, "kind") == "top_level_comment"))

    %{
      "issueCommentCount" => length(issue_comments),
      "reviewCount" => length(reviews),
      "reviewCommentCount" => length(review_comments),
      "reviewThreadCount" => review_thread_count,
      "reviewReplyCount" => review_reply_count,
      "unrepliedReviewThreadCount" => unreplied_review_thread_count,
      "actionableTopLevelCommentCount" => actionable_top_level_comment_count,
      "reviewStateCounts" => review_state_counts,
      "approvalCount" => Map.get(review_state_counts, "approved", 0),
      "changeRequestCount" => change_request_count,
      "hasDiscussion" => Enum.any?([issue_comments, reviews, review_comments], &(&1 != [])),
      "hasTopLevelComments" => top_level_comment_count > 0,
      "hasChangeRequests" => change_request_count > 0,
      "hasUnrepliedReviewThreads" => unreplied_review_thread_count > 0,
      "actionableFeedbackCount" => actionable_feedback_count,
      "hasActionableFeedback" => actionable_feedback_count > 0
    }
  end

  defp actionable_items(repo, args, issue_comments, reviews, review_comments) do
    top_level_comment_items(repo, args, issue_comments) ++
      change_request_items(repo, args, reviews) ++
      unreplied_review_thread_items(repo, args, review_comments)
  end

  defp unresolved_feedback_summary(actionable) do
    response_actions =
      actionable
      |> Enum.map(&Map.get(&1, "responseAction"))
      |> Enum.reject(&is_nil/1)

    %{
      "hasUnresolvedFeedback" => actionable != [],
      "unresolvedCount" => length(actionable),
      "unresolvedKinds" => actionable |> Enum.map(&Map.get(&1, "kind")) |> Enum.frequencies(),
      "unresolvedItems" => Enum.map(actionable, &unresolved_feedback_item/1),
      "nextResponseActions" => response_actions,
      "unsupportedResponseCount" => length(actionable) - length(response_actions),
      "responseTools" =>
        actionable
        |> Enum.map(&Map.get(&1, "responseTool"))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp unresolved_feedback_item(item) when is_map(item) do
    kind = Map.get(item, "kind")

    compact_map(%{
      "kind" => kind,
      "id" => feedback_item_id(item),
      "commentId" => Map.get(item, "commentId"),
      "reviewId" => Map.get(item, "reviewId"),
      "path" => Map.get(item, "path"),
      "author" => Map.get(item, "author"),
      "agentAction" => feedback_agent_action(kind),
      "responseCapability" => Map.get(item, "responseCapability"),
      "responseTool" => Map.get(item, "responseTool"),
      "responseAction" => Map.get(item, "responseAction")
    })
  end

  defp feedback_item_id(%{"commentId" => comment_id}) when is_binary(comment_id), do: comment_id
  defp feedback_item_id(%{"reviewId" => review_id}) when is_binary(review_id), do: review_id
  defp feedback_item_id(_item), do: nil

  defp feedback_agent_action("top_level_comment"), do: "post_top_level_response"
  defp feedback_agent_action("change_request"), do: "post_change_request_response"
  defp feedback_agent_action("unreplied_review_thread"), do: "reply_inline_thread"
  defp feedback_agent_action(_kind), do: "inspect_feedback"

  defp feedback_action_policy(repo, args) do
    %{
      "topLevelComment" =>
        feedback_action(
          repo,
          @add_comment_tool,
          @add_comment_capability,
          "top-level PR comments",
          args,
          ["body"]
        ),
      "inlineThreadReply" =>
        feedback_action(
          repo,
          @reply_review_comment_tool,
          @reply_review_comment_capability,
          "inline review thread replies",
          args,
          ["comment_id", "body"]
        ),
      "submitReview" =>
        feedback_action(
          repo,
          @submit_review_tool,
          @submit_review_capability,
          "formal PR reviews",
          args,
          ["event", "body"],
          %{},
          %{"allowedEvents" => ["comment", "approve", "request_changes"]}
        )
    }
  end

  defp feedback_action(repo, tool, capability, description, args, required_arguments, extra_arguments \\ %{}, extra_fields \\ %{}) do
    if supported?(repo, tool) do
      %{
        "supported" => true,
        "tool" => tool,
        "workflowCapability" => capability,
        "description" => description,
        "prefilledArguments" => response_arguments(args, extra_arguments),
        "requiredArguments" => required_arguments
      }
      |> Map.merge(extra_fields)
    else
      %{
        "supported" => false,
        "workflowCapability" => capability,
        "reason" => "provider_capability_not_available",
        "description" => description
      }
    end
  end

  defp response_action(repo, tool, capability, args, required_arguments, extra_arguments \\ %{}) do
    if supported?(repo, tool) do
      %{
        "tool" => tool,
        "workflowCapability" => capability,
        "prefilledArguments" => response_arguments(args, extra_arguments),
        "requiredArguments" => required_arguments
      }
    end
  end

  defp response_arguments(args, extra_arguments) do
    args
    |> response_target_arguments()
    |> Map.merge(extra_arguments)
    |> compact_map()
  end

  defp response_target_arguments(%{url: url}) when is_binary(url) and url != "",
    do: %{"url" => url}

  defp response_target_arguments(%{branch: branch}) when is_binary(branch) and branch != "",
    do: %{"branch" => branch}

  defp response_target_arguments(%{number: number}) when is_binary(number) and number != "",
    do: %{"number" => number}

  defp response_target_arguments(_args), do: %{}

  defp review_threads(repo, args, review_comments) do
    replies_by_parent =
      review_comments
      |> Enum.filter(&review_comment_reply?/1)
      |> Enum.group_by(&review_comment_reply_to_id/1, &normalized_review_comment/1)

    review_comments
    |> Enum.filter(&top_level_review_comment?/1)
    |> Enum.map(fn comment ->
      comment_id = review_comment_id(comment)
      replies = Map.get(replies_by_parent, comment_id, [])

      compact_map(%{
        "commentId" => comment_id,
        "path" => text_field(comment, "path", :path),
        "body" => text_field(comment, "body", :body),
        "author" => user_login(comment),
        "createdAt" => text_field(comment, "created_at", :created_at),
        "updatedAt" => text_field(comment, "updated_at", :updated_at),
        "replyCount" => length(replies),
        "resolved" => replies != [],
        "resolutionState" => if(replies == [], do: "needs_response", else: "responded"),
        "responseCapability" =>
          if(replies == [] and supported?(repo, @reply_review_comment_tool),
            do: @reply_review_comment_capability
          ),
        "responseTool" =>
          if(replies == [] and supported?(repo, @reply_review_comment_tool),
            do: @reply_review_comment_tool
          ),
        "responseAction" =>
          if replies == [] do
            response_action(
              repo,
              @reply_review_comment_tool,
              @reply_review_comment_capability,
              args,
              ["body"],
              %{"comment_id" => comment_id}
            )
          end,
        "replies" => replies
      })
    end)
  end

  defp normalized_review_comment(comment) when is_map(comment) do
    compact_map(%{
      "commentId" => review_comment_id(comment),
      "inReplyToId" => review_comment_reply_to_id(comment),
      "path" => text_field(comment, "path", :path),
      "body" => text_field(comment, "body", :body),
      "author" => user_login(comment),
      "createdAt" => text_field(comment, "created_at", :created_at),
      "updatedAt" => text_field(comment, "updated_at", :updated_at)
    })
  end

  defp top_level_comment_items(repo, args, issue_comments) do
    responded_ids = top_level_response_comment_ids(issue_comments)

    issue_comments
    |> Enum.reject(fn comment ->
      top_level_response_comment?(comment) or
        MapSet.member?(responded_ids, review_comment_id(comment))
    end)
    |> Enum.map(fn comment ->
      comment_id = review_comment_id(comment)

      compact_map(%{
        "kind" => "top_level_comment",
        "commentId" => comment_id,
        "body" => text_field(comment, "body", :body),
        "author" => user_login(comment),
        "createdAt" => text_field(comment, "created_at", :created_at),
        "updatedAt" => text_field(comment, "updated_at", :updated_at),
        "responseCapability" => if(supported?(repo, @add_comment_tool), do: @add_comment_capability),
        "responseTool" => if(supported?(repo, @add_comment_tool), do: @add_comment_tool),
        "responseAction" =>
          response_action(repo, @add_comment_tool, @add_comment_capability, args, ["body"], %{
            "reply_to_comment_id" => comment_id
          })
      })
    end)
  end

  defp change_request_items(repo, args, reviews) do
    reviews
    |> Enum.filter(&(review_state(&1) == "changes_requested"))
    |> Enum.map(fn review ->
      compact_map(%{
        "kind" => "change_request",
        "reviewId" => review_id(review),
        "body" => text_field(review, "body", :body),
        "author" => user_login(review),
        "submittedAt" => text_field(review, "submitted_at", :submitted_at),
        "createdAt" => text_field(review, "created_at", :created_at),
        "responseCapability" => if(supported?(repo, @add_comment_tool), do: @add_comment_capability),
        "responseTool" => if(supported?(repo, @add_comment_tool), do: @add_comment_tool),
        "responseAction" => response_action(repo, @add_comment_tool, @add_comment_capability, args, ["body"])
      })
    end)
  end

  defp unreplied_review_thread_items(repo, args, review_comments) do
    replied_ids = replied_review_comment_ids(review_comments)

    review_comments
    |> Enum.filter(fn comment ->
      top_level_review_comment?(comment) and
        not MapSet.member?(replied_ids, review_comment_id(comment))
    end)
    |> Enum.map(fn comment ->
      compact_map(%{
        "kind" => "unreplied_review_thread",
        "commentId" => review_comment_id(comment),
        "body" => text_field(comment, "body", :body),
        "author" => user_login(comment),
        "path" => text_field(comment, "path", :path),
        "createdAt" => text_field(comment, "created_at", :created_at),
        "updatedAt" => text_field(comment, "updated_at", :updated_at),
        "responseCapability" =>
          if(supported?(repo, @reply_review_comment_tool),
            do: @reply_review_comment_capability
          ),
        "responseTool" => if(supported?(repo, @reply_review_comment_tool), do: @reply_review_comment_tool),
        "responseAction" =>
          response_action(
            repo,
            @reply_review_comment_tool,
            @reply_review_comment_capability,
            args,
            ["body"],
            %{"comment_id" => review_comment_id(comment)}
          )
      })
    end)
  end

  defp review_thread_count(review_comments),
    do: Enum.count(review_comments, &top_level_review_comment?/1)

  defp review_reply_count(review_comments),
    do: Enum.count(review_comments, &review_comment_reply?/1)

  defp unreplied_review_thread_count(review_comments) do
    replied_ids = replied_review_comment_ids(review_comments)

    Enum.count(review_comments, fn comment ->
      top_level_review_comment?(comment) and
        not MapSet.member?(replied_ids, review_comment_id(comment))
    end)
  end

  defp replied_review_comment_ids(review_comments) do
    review_comments
    |> Enum.flat_map(fn comment ->
      case review_comment_reply_to_id(comment) do
        nil -> []
        id -> [id]
      end
    end)
    |> MapSet.new()
  end

  defp top_level_review_comment?(comment), do: is_nil(review_comment_reply_to_id(comment))
  defp review_comment_reply?(comment), do: not top_level_review_comment?(comment)

  defp review_id(review) when is_map(review) do
    review
    |> Map.get("id", Map.get(review, :id))
    |> normalized_id()
  end

  defp review_id(_review), do: nil

  defp review_comment_reply_to_id(comment) when is_map(comment) do
    comment
    |> Map.get("in_reply_to_id", Map.get(comment, :in_reply_to_id))
    |> normalized_id()
  end

  defp review_comment_reply_to_id(_comment), do: nil

  defp review_comment_id(comment) when is_map(comment) do
    comment
    |> Map.get("id", Map.get(comment, :id))
    |> normalized_id()
  end

  defp review_comment_id(_comment), do: nil

  defp top_level_response_comment_ids(issue_comments) when is_list(issue_comments) do
    issue_comments
    |> Enum.flat_map(fn comment ->
      case top_level_response_target_id(comment) do
        nil -> []
        id -> [id]
      end
    end)
    |> MapSet.new()
  end

  defp canonical_top_level_comment_id(issue_comments, target_id)
       when is_list(issue_comments) and is_binary(target_id) do
    comment_ids =
      issue_comments
      |> Enum.map(&review_comment_id/1)
      |> Enum.reject(&is_nil/1)

    cond do
      target_id in comment_ids ->
        target_id

      true ->
        case Enum.filter(comment_ids, &near_decimal_id?(&1, target_id)) do
          [canonical_id] -> canonical_id
          _other -> target_id
        end
    end
  end

  defp canonical_top_level_comment_id(_issue_comments, target_id), do: target_id

  defp near_decimal_id?(candidate, target) when is_binary(candidate) and is_binary(target) do
    with true <- String.match?(candidate, ~r/^\d+$/),
         true <- String.match?(target, ~r/^\d+$/),
         {candidate_int, ""} <- Integer.parse(candidate),
         {target_int, ""} <- Integer.parse(target) do
      # CNB ids can exceed JavaScript's safe integer range and may be rounded by
      # MCP/LLM clients before the typed response tool is called.
      abs(candidate_int - target_int) <= 1024
    else
      _other -> false
    end
  end

  defp top_level_response_comment?(comment), do: not is_nil(top_level_response_target_id(comment))

  defp top_level_response_target_id(comment) when is_map(comment) do
    comment
    |> text_field("body", :body)
    |> response_marker_target_id()
  end

  defp top_level_response_target_id(_comment), do: nil

  defp response_marker_target_id(body) when is_binary(body) do
    case Regex.run(~r/<!--\s*symphony:response-to-pr-comment:([^>\s]+)\s*-->/, body, capture: :all_but_first) do
      [id] -> normalized_id(id)
      _other -> nil
    end
  end

  defp response_marker_target_id(_body), do: nil

  defp body_with_top_level_response_marker(body, nil), do: body

  defp body_with_top_level_response_marker(body, reply_to_comment_id)
       when is_binary(body) and is_binary(reply_to_comment_id) do
    marker = "<!-- symphony:response-to-pr-comment:#{reply_to_comment_id} -->"

    if String.contains?(body, marker) do
      body
    else
      body <> "\n\n" <> marker
    end
  end

  defp normalized_id(nil), do: nil
  defp normalized_id(""), do: nil
  defp normalized_id(id) when is_binary(id), do: id
  defp normalized_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalized_id(id), do: to_string(id)

  defp text_field(map, string_key, atom_key) when is_map(map) do
    case Map.get(map, string_key, Map.get(map, atom_key)) do
      value when is_binary(value) -> String.trim(value)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_atom(value) -> value |> Atom.to_string() |> String.trim()
      _value -> nil
    end
  end

  defp text_field(_map, _string_key, _atom_key), do: nil

  defp user_login(map) when is_map(map) do
    case Map.get(map, "user", Map.get(map, :user)) do
      user when is_map(user) -> text_field(user, "login", :login)
      _user -> nil
    end
  end

  defp user_login(_map), do: nil

  defp compact_map(map) do
    Map.reject(map, fn {_key, value} -> value in [nil, ""] end)
  end

  defp review_state_counts(reviews) when is_list(reviews) do
    Enum.reduce(reviews, %{}, fn review, acc ->
      Map.update(acc, review_state(review), 1, &(&1 + 1))
    end)
  end

  defp review_state(review) when is_map(review) do
    review
    |> review_state_value()
    |> normalize_review_state()
  end

  defp review_state(_review), do: "unknown"

  defp review_state_value(review) do
    Map.get(review, "state") ||
      Map.get(review, :state) ||
      Map.get(review, "reviewState") ||
      Map.get(review, :review_state) ||
      Map.get(review, :reviewState)
  end

  defp normalize_review_state(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s-]+/, "_")
    |> canonical_review_state()
  end

  defp normalize_review_state(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_review_state()

  defp normalize_review_state(_value), do: "unknown"

  defp canonical_review_state(""), do: "unknown"
  defp canonical_review_state("approve"), do: "approved"
  defp canonical_review_state("approved"), do: "approved"
  defp canonical_review_state("change_requested"), do: "changes_requested"
  defp canonical_review_state("changes_requested"), do: "changes_requested"
  defp canonical_review_state("request_changes"), do: "changes_requested"
  defp canonical_review_state("comment"), do: "commented"
  defp canonical_review_state("commented"), do: "commented"
  defp canonical_review_state("pending"), do: "pending"
  defp canonical_review_state("dismissed"), do: "dismissed"
  defp canonical_review_state(state), do: state

  defp snapshot_warnings(%{"checks" => checks}), do: checks_warnings(checks)
  defp snapshot_warnings(_snapshot), do: []

  defp checks_warnings(%{"runs" => []}) do
    [
      %{
        "code" => "checks_unavailable",
        "message" => "No checks are reported for this change proposal.",
        "details" => %{}
      }
    ]
  end

  defp checks_warnings(_checks), do: []

  defp success_payload(data, warnings \\ []) do
    %{
      "data" => Serializer.json_safe_value(data),
      "warnings" => Serializer.json_safe_value(warnings)
    }
  end

  defp typed_failure(reason) do
    {code, message, details} = typed_error(reason)
    {:failure, %{"error" => %{"code" => code, "message" => message, "details" => details}}}
  end

  defp typed_error({:invalid_arguments, message}), do: {"invalid_arguments", message, %{}}

  defp typed_error(%Error{} = error) do
    {
      error.code |> to_string(),
      error.message || "Repo provider typed workflow tool execution failed.",
      %{
        "provider" => error.provider,
        "operation" => error.operation && to_string(error.operation),
        "retryable" => error.retryable?,
        "details" => Serializer.json_safe_value(error.details)
      }
    }
  end

  defp typed_error(reason) do
    {"provider_request_failed", "Repo provider typed workflow tool execution failed.", %{"reason" => inspect(reason)}}
  end

  defp unsupported_tool(repo) do
    {:failure,
     %{
       "error" => %{
         "code" => "unsupported_tool",
         "message" => "Unsupported repo-provider dynamic tool.",
         "supportedTools" => supported_tool_names(repo)
       }
     }}
  end

  defp blank?(value), do: not (is_binary(value) and String.trim(value) != "")
end
