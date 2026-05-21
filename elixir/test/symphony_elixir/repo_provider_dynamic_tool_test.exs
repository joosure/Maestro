defmodule SymphonyElixir.RepoProviderDynamicToolTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Agent.Runtime.Target

  setup do
    Application.put_env(:symphony_elixir, :memory_repo_provider_recipient, self())

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :memory_repo_provider_recipient)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_pr)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_issue_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_reviews)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_review_comments)
      Application.delete_env(:symphony_elixir, :memory_repo_provider_checks)
    end)

    :ok
  end

  test "repo-provider typed tools advertise production metadata and resolve inventory capabilities" do
    context = repo_tool_context()
    names = Enum.map(context.tool_specs, &Map.fetch!(&1, "name"))

    assert Enum.sort(names) ==
             Enum.sort([
               "repo_change_proposal_snapshot",
               "repo_create_or_update_change_proposal",
               "repo_read_change_proposal_discussion",
               "repo_add_change_proposal_comment",
               "repo_submit_change_proposal_review",
               "repo_reply_change_proposal_review_comment",
               "repo_read_change_proposal_checks",
               "repo_merge_change_proposal",
               "repo_close_change_proposal"
             ])

    assert context.tool_metadata["repo_change_proposal_snapshot"]["workflowCapability"] ==
             "repo.change_proposal_snapshot"

    assert context.tool_metadata["repo_change_proposal_snapshot"]["sourceKind"] == "memory"
    assert context.tool_metadata["repo_change_proposal_snapshot"]["sideEffect"] == "read_only"
    assert context.tool_metadata["repo_create_or_update_change_proposal"]["sideEffect"] == "write"
    assert context.tool_metadata["repo_add_change_proposal_comment"]["sideEffect"] == "write"
    assert context.tool_metadata["repo_submit_change_proposal_review"]["sideEffect"] == "write"

    assert context.tool_metadata["repo_reply_change_proposal_review_comment"]["sideEffect"] ==
             "write"

    assert context.tool_metadata["repo_merge_change_proposal"]["sideEffect"] == "destructive"

    create_spec =
      Enum.find(context.tool_specs, &(&1["name"] == "repo_create_or_update_change_proposal"))

    assert create_spec["description"] =~ "If body is provided it must be one JSON string"
    assert create_spec["description"] =~ "idempotent by head branch"

    assert get_in(create_spec, ["inputSchema", "properties", "body", "description"]) =~
             "one JSON string"

    assert get_in(create_spec, ["inputSchema", "properties", "body", "description"]) =~
             "configured deterministic default"

    assert get_in(create_spec, ["inputSchema", "properties", "branch", "description"]) =~
             "lookup/update"

    assert get_in(create_spec, ["inputSchema", "properties", "head", "description"]) =~
             "source branch"

    assert %{
             "if" => %{
               "properties" => %{"mode" => %{"const" => "create"}},
               "required" => ["mode"]
             },
             "then" => %{
               "required" => ["title", "base", "head"],
               "properties" => %{
                 "title" => %{"type" => "string", "minLength" => 1},
                 "base" => %{"type" => "string", "minLength" => 1},
                 "head" => %{"type" => "string", "minLength" => 1}
               }
             }
           } in get_in(create_spec, ["inputSchema", "allOf"])

    assert {:ok, resolved} =
             Inventory.resolve_required(context, [
               "repo.change_proposal_snapshot",
               "repo.create_or_update_change_proposal",
               "repo.read_change_proposal_discussion",
               "repo.add_change_proposal_comment",
               "repo.submit_change_proposal_review",
               "repo.reply_change_proposal_review_comment",
               "repo.read_change_proposal_checks",
               "repo.merge_change_proposal",
               "repo.close_change_proposal"
             ])

    assert Enum.map(resolved, & &1.tool) == [
             "repo_change_proposal_snapshot",
             "repo_create_or_update_change_proposal",
             "repo_read_change_proposal_discussion",
             "repo_add_change_proposal_comment",
             "repo_submit_change_proposal_review",
             "repo_reply_change_proposal_review_comment",
             "repo_read_change_proposal_checks",
             "repo_merge_change_proposal",
             "repo_close_change_proposal"
           ]
  end

  test "repo change proposal snapshot can include discussion and checks" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, memory_pr())

    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [
      %{"id" => 1, "body" => "ship it"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [
      %{"id" => 2, "state" => "APPROVED"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [
      %{"id" => 3, "body" => "nit"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_checks, [
      %{"name" => "ci", "bucket" => "pass"}
    ])

    assert {:success,
            %{
              "data" => %{
                "changeProposal" => %{"number" => 20, "state" => "OPEN"},
                "discussion" => %{
                  "issueComments" => [%{"id" => 1}],
                  "reviews" => [%{"id" => 2}],
                  "reviewComments" => [%{"id" => 3}],
                  "reviewThreads" => [
                    %{
                      "commentId" => "3",
                      "replyCount" => 0,
                      "resolved" => false,
                      "resolutionState" => "needs_response",
                      "responseCapability" => "repo.reply_change_proposal_review_comment",
                      "responseTool" => "repo_reply_change_proposal_review_comment"
                    }
                  ],
                  "summary" => %{
                    "issueCommentCount" => 1,
                    "reviewCount" => 1,
                    "reviewCommentCount" => 1,
                    "reviewStateCounts" => %{"approved" => 1},
                    "approvalCount" => 1,
                    "changeRequestCount" => 0,
                    "hasDiscussion" => true,
                    "hasChangeRequests" => false
                  }
                },
                "checks" => %{"runs" => [%{"name" => "ci"}], "summary" => %{"pass" => 1}}
              },
              "warnings" => []
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_change_proposal_snapshot",
               %{"number" => "20", "include_discussion" => true, "include_checks" => true}
             )
  end

  test "repo change proposal snapshot reports missing proposal as business state" do
    assert {:success,
            %{
              "data" => %{
                "exists" => false,
                "changeProposal" => nil,
                "lookup" => %{
                  "provider" => "memory",
                  "selector" => %{"kind" => "number", "value" => "20"}
                },
                "discussion" => nil,
                "checks" => nil
              },
              "warnings" => []
            }} =
             DynamicTool.execute(repo_tool_context(), "repo_change_proposal_snapshot", %{
               "number" => "20"
             })
  end

  test "repo change proposal snapshot maps GitHub not found to exists false" do
    context = repo_tool_context(%{provider: %{kind: "github", repository: "acme/widgets"}})

    runner = fn
      "gh", ["pr", "view", "42", "--repo", "acme/widgets", "--json", _fields] ->
        {:error, {1, "no pull requests found for branch \"feature/no-pr\"\n"}}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:success,
            %{
              "data" => %{
                "exists" => false,
                "changeProposal" => nil,
                "lookup" => %{
                  "provider" => "github",
                  "selector" => %{"kind" => "number", "value" => "42"}
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_change_proposal_snapshot",
               %{"number" => "42"},
               command_runner: runner
             )
  end

  test "repo change proposal snapshot accepts CNB pull request URLs as typed selectors" do
    context = repo_tool_context(cnb_repo())
    names = Enum.map(context.tool_specs, &Map.fetch!(&1, "name"))

    refute "repo_submit_change_proposal_review" in names

    requester = fn
      :get, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42", _headers, nil ->
        {:ok, 200,
         %{
           "number" => "42",
           "state" => "open",
           "title" => "Typed TAPD CNB validation",
           "body" => "Created by typed repo-provider tool.",
           "head" => %{"ref" => "refs/heads/symphony-tapd-cnb-typed", "sha" => "abc123"},
           "base" => %{"ref" => "refs/heads/main"},
           "mergeable_state" => "mergeable",
           "blocked_on" => "unblocked",
           "is_wip" => false
         }}

      method, url, _headers, body ->
        flunk("unexpected CNB request: #{inspect({method, url, body})}")
    end

    assert {:success,
            %{
              "data" => %{
                "exists" => true,
                "changeProposal" => %{
                  "number" => 42,
                  "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
                  "state" => "OPEN"
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_change_proposal_snapshot",
               %{"url" => "https://cnb.cool/acme/widgets/-/pulls/42"},
               token: "test-token",
               requester: requester
             )
  end

  test "repo discussion tool accepts GitHub pull request URLs as typed selectors" do
    context = repo_tool_context(%{provider: %{kind: "github", repository: "example-user/sample-repo"}})

    runner = fn
      "gh",
      [
        "api",
        "repos/example-user/sample-repo/issues/45/comments",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!([%{"id" => 1, "body" => "top-level feedback"}])}

      "gh",
      [
        "api",
        "repos/example-user/sample-repo/pulls/45/reviews",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!([])}

      "gh",
      [
        "api",
        "repos/example-user/sample-repo/pulls/45/comments",
        "--method",
        "GET",
        "-F",
        "page=1",
        "-F",
        "per_page=100"
      ] ->
        {:ok, Jason.encode!([])}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:success,
            %{
              "data" => %{
                "discussion" => %{
                  "issueComments" => [%{"id" => 1, "body" => "top-level feedback"}],
                  "reviews" => [],
                  "reviewComments" => [],
                  "summary" => %{"issueCommentCount" => 1}
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_read_change_proposal_discussion",
               %{"url" => "https://github.com/example-user/sample-repo/pull/45"},
               command_runner: runner
             )
  end

  test "repo checks tool reports empty checks as success with warning" do
    assert {:success,
            %{
              "data" => %{"checks" => %{"runs" => [], "summary" => %{}}},
              "warnings" => [
                %{
                  "code" => "checks_unavailable",
                  "message" => "No checks are reported for this change proposal.",
                  "details" => %{}
                }
              ]
            }} =
             DynamicTool.execute(repo_tool_context(), "repo_read_change_proposal_checks", %{
               "number" => "20"
             })
  end

  test "repo snapshot reports empty included checks as success with warning" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, memory_pr())

    assert {:success,
            %{
              "data" => %{
                "exists" => true,
                "changeProposal" => %{"number" => 20},
                "checks" => %{"runs" => [], "summary" => %{}}
              },
              "warnings" => [%{"code" => "checks_unavailable"}]
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_change_proposal_snapshot",
               %{"number" => "20", "include_checks" => true}
             )
  end

  test "repo discussion tool honors explicit false include flags" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [
      %{"id" => 1, "body" => "ship it"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [
      %{"id" => 2, "state" => "APPROVED"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [
      %{"id" => 3, "body" => "nit"}
    ])

    assert {:success,
            %{
              "data" => %{
                "discussion" => %{
                  "issueComments" => [],
                  "reviews" => [],
                  "reviewComments" => [],
                  "summary" => %{
                    "issueCommentCount" => 0,
                    "reviewCount" => 0,
                    "reviewCommentCount" => 0,
                    "reviewStateCounts" => %{},
                    "approvalCount" => 0,
                    "changeRequestCount" => 0,
                    "hasDiscussion" => false,
                    "hasChangeRequests" => false
                  }
                }
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_read_change_proposal_discussion",
               %{
                 "number" => "20",
                 "include_issue_comments" => false,
                 "include_reviews" => false,
                 "include_review_comments" => false
               }
             )
  end

  test "repo discussion tool returns normalized review summary" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [
      %{"id" => 1, "body" => "Please add a note", "user" => %{"login" => "reviewer"}},
      %{"id" => 2, "body" => "Please update docs"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_reviews, [
      %{"id" => 3, "state" => "APPROVED"},
      %{"id" => 4, "state" => "CHANGES_REQUESTED"},
      %{"id" => 5, "state" => "request-changes"},
      %{"id" => 6, "reviewState" => "COMMENTED"}
    ])

    Application.put_env(:symphony_elixir, :memory_repo_provider_review_comments, [
      %{"id" => 7, "body" => "first thread"},
      %{
        "id" => 8,
        "body" => "second thread",
        "path" => "lib/example.ex",
        "user" => %{"login" => "reviewer"}
      },
      %{"id" => 9, "body" => "reply", "in_reply_to_id" => 7}
    ])

    assert {:success,
            %{
              "data" => %{
                "discussion" => %{
                  "actionableItems" => [
                    %{
                      "kind" => "top_level_comment",
                      "commentId" => "1",
                      "body" => "Please add a note",
                      "author" => "reviewer",
                      "responseCapability" => "repo.add_change_proposal_comment",
                      "responseTool" => "repo_add_change_proposal_comment",
                      "responseAction" => %{
                        "tool" => "repo_add_change_proposal_comment",
                        "workflowCapability" => "repo.add_change_proposal_comment",
                        "prefilledArguments" => %{"number" => "20", "reply_to_comment_id" => "1"},
                        "requiredArguments" => ["body"]
                      }
                    },
                    %{
                      "kind" => "top_level_comment",
                      "commentId" => "2",
                      "body" => "Please update docs",
                      "responseCapability" => "repo.add_change_proposal_comment",
                      "responseTool" => "repo_add_change_proposal_comment",
                      "responseAction" => %{
                        "prefilledArguments" => %{"number" => "20", "reply_to_comment_id" => "2"},
                        "requiredArguments" => ["body"]
                      }
                    },
                    %{"kind" => "change_request", "reviewId" => "4"},
                    %{"kind" => "change_request", "reviewId" => "5"},
                    %{
                      "kind" => "unreplied_review_thread",
                      "commentId" => "8",
                      "body" => "second thread",
                      "author" => "reviewer",
                      "path" => "lib/example.ex",
                      "responseCapability" => "repo.reply_change_proposal_review_comment",
                      "responseTool" => "repo_reply_change_proposal_review_comment",
                      "responseAction" => %{
                        "tool" => "repo_reply_change_proposal_review_comment",
                        "workflowCapability" => "repo.reply_change_proposal_review_comment",
                        "prefilledArguments" => %{"number" => "20", "comment_id" => "8"},
                        "requiredArguments" => ["body"]
                      }
                    }
                  ],
                  "reviewThreads" => [
                    %{
                      "commentId" => "7",
                      "body" => "first thread",
                      "replyCount" => 1,
                      "resolved" => true,
                      "resolutionState" => "responded",
                      "replies" => [
                        %{"commentId" => "9", "inReplyToId" => "7", "body" => "reply"}
                      ]
                    },
                    %{
                      "commentId" => "8",
                      "body" => "second thread",
                      "author" => "reviewer",
                      "path" => "lib/example.ex",
                      "replyCount" => 0,
                      "resolved" => false,
                      "resolutionState" => "needs_response",
                      "responseCapability" => "repo.reply_change_proposal_review_comment",
                      "responseTool" => "repo_reply_change_proposal_review_comment",
                      "responseAction" => %{
                        "tool" => "repo_reply_change_proposal_review_comment",
                        "workflowCapability" => "repo.reply_change_proposal_review_comment",
                        "prefilledArguments" => %{"number" => "20", "comment_id" => "8"},
                        "requiredArguments" => ["body"]
                      },
                      "replies" => []
                    }
                  ],
                  "feedbackActionPolicy" => %{
                    "topLevelComment" => %{
                      "supported" => true,
                      "tool" => "repo_add_change_proposal_comment",
                      "prefilledArguments" => %{"number" => "20"},
                      "requiredArguments" => ["body"]
                    },
                    "inlineThreadReply" => %{
                      "supported" => true,
                      "tool" => "repo_reply_change_proposal_review_comment",
                      "prefilledArguments" => %{"number" => "20"},
                      "requiredArguments" => ["comment_id", "body"]
                    },
                    "submitReview" => %{
                      "supported" => true,
                      "tool" => "repo_submit_change_proposal_review",
                      "prefilledArguments" => %{"number" => "20"},
                      "requiredArguments" => ["event", "body"],
                      "allowedEvents" => ["comment", "approve", "request_changes"]
                    }
                  },
                  "unresolvedFeedbackSummary" => %{
                    "hasUnresolvedFeedback" => true,
                    "unresolvedCount" => 5,
                    "unresolvedKinds" => %{
                      "top_level_comment" => 2,
                      "change_request" => 2,
                      "unreplied_review_thread" => 1
                    },
                    "unresolvedItems" => [
                      %{
                        "kind" => "top_level_comment",
                        "id" => "1",
                        "commentId" => "1",
                        "agentAction" => "post_top_level_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      },
                      %{
                        "kind" => "top_level_comment",
                        "id" => "2",
                        "commentId" => "2",
                        "agentAction" => "post_top_level_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      },
                      %{
                        "kind" => "change_request",
                        "id" => "4",
                        "reviewId" => "4",
                        "agentAction" => "post_change_request_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      },
                      %{
                        "kind" => "change_request",
                        "id" => "5",
                        "reviewId" => "5",
                        "agentAction" => "post_change_request_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      },
                      %{
                        "kind" => "unreplied_review_thread",
                        "id" => "8",
                        "commentId" => "8",
                        "agentAction" => "reply_inline_thread",
                        "responseTool" => "repo_reply_change_proposal_review_comment"
                      }
                    ],
                    "nextResponseActions" => [
                      %{"tool" => "repo_add_change_proposal_comment"},
                      %{"tool" => "repo_add_change_proposal_comment"},
                      %{"tool" => "repo_add_change_proposal_comment"},
                      %{"tool" => "repo_add_change_proposal_comment"},
                      %{"tool" => "repo_reply_change_proposal_review_comment"}
                    ],
                    "unsupportedResponseCount" => 0,
                    "responseTools" => [
                      "repo_add_change_proposal_comment",
                      "repo_reply_change_proposal_review_comment"
                    ]
                  },
                  "summary" => %{
                    "issueCommentCount" => 2,
                    "reviewCount" => 4,
                    "reviewCommentCount" => 3,
                    "reviewThreadCount" => 2,
                    "reviewReplyCount" => 1,
                    "unrepliedReviewThreadCount" => 1,
                    "actionableTopLevelCommentCount" => 2,
                    "reviewStateCounts" => %{
                      "approved" => 1,
                      "changes_requested" => 2,
                      "commented" => 1
                    },
                    "approvalCount" => 1,
                    "changeRequestCount" => 2,
                    "hasDiscussion" => true,
                    "hasTopLevelComments" => true,
                    "hasChangeRequests" => true,
                    "hasUnrepliedReviewThreads" => true,
                    "actionableFeedbackCount" => 5,
                    "hasActionableFeedback" => true
                  }
                }
              }
            }} =
             DynamicTool.execute(repo_tool_context(), "repo_read_change_proposal_discussion", %{
               "number" => "20"
             })
  end

  test "CNB feedback discussion marks submit review unsupported without exposing the tool" do
    context = repo_tool_context(cnb_repo())
    names = Enum.map(context.tool_specs, &Map.fetch!(&1, "name"))

    refute "repo_submit_change_proposal_review" in names

    requester = fn
      :get, url, _headers, nil ->
        cond do
          url == "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200,
             %{
               "number" => "42",
               "state" => "open",
               "title" => "Typed feedback",
               "head" => %{"ref" => "refs/heads/typed-feedback"},
               "base" => %{"ref" => "refs/heads/main"}
             }}

          String.starts_with?(url, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42/comments?") ->
            {:ok, 200, [%{"id" => 1, "body" => "Please update docs"}]}

          String.starts_with?(url, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42/reviews?") ->
            {:ok, 200, [%{"id" => 2, "state" => "changes_requested"}]}

          String.starts_with?(url, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42/reviews/2/comments?") ->
            {:ok, 200, []}

          true ->
            flunk("unexpected CNB GET request: #{inspect(url)}")
        end

      method, url, _headers, body ->
        flunk("unexpected CNB request: #{inspect({method, url, body})}")
    end

    assert {:success,
            %{
              "data" => %{
                "discussion" => %{
                  "feedbackActionPolicy" => %{
                    "submitReview" => %{
                      "supported" => false,
                      "workflowCapability" => "repo.submit_change_proposal_review",
                      "reason" => "provider_capability_not_available"
                    },
                    "topLevelComment" => %{
                      "supported" => true,
                      "tool" => "repo_add_change_proposal_comment",
                      "prefilledArguments" => %{"number" => "42"},
                      "requiredArguments" => ["body"]
                    },
                    "inlineThreadReply" => %{
                      "supported" => true,
                      "tool" => "repo_reply_change_proposal_review_comment",
                      "prefilledArguments" => %{"number" => "42"},
                      "requiredArguments" => ["comment_id", "body"]
                    }
                  },
                  "actionableItems" => [
                    %{
                      "kind" => "top_level_comment",
                      "responseTool" => "repo_add_change_proposal_comment",
                      "responseAction" => %{
                        "prefilledArguments" => %{"number" => "42", "reply_to_comment_id" => "1"},
                        "requiredArguments" => ["body"]
                      }
                    },
                    %{
                      "kind" => "change_request",
                      "responseTool" => "repo_add_change_proposal_comment",
                      "responseAction" => %{
                        "prefilledArguments" => %{"number" => "42"},
                        "requiredArguments" => ["body"]
                      }
                    }
                  ],
                  "unresolvedFeedbackSummary" => %{
                    "hasUnresolvedFeedback" => true,
                    "unresolvedCount" => 2,
                    "unsupportedResponseCount" => 0,
                    "unresolvedItems" => [
                      %{
                        "kind" => "top_level_comment",
                        "agentAction" => "post_top_level_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      },
                      %{
                        "kind" => "change_request",
                        "agentAction" => "post_change_request_response",
                        "responseTool" => "repo_add_change_proposal_comment"
                      }
                    ],
                    "nextResponseActions" => [
                      %{"tool" => "repo_add_change_proposal_comment"},
                      %{"tool" => "repo_add_change_proposal_comment"}
                    ]
                  }
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_read_change_proposal_discussion",
               %{"number" => "42"},
               token: "test-token",
               requester: requester
             )

    assert %{
             "success" => false,
             "payload" => %{
               "error" => %{
                 "code" => "unsupported_tool",
                 "supportedTools" => supported_tools
               }
             }
           } =
             Bridge.execute(
               "repo_submit_change_proposal_review",
               %{"number" => "42", "event" => "request_changes", "body" => "Please update docs"},
               tool_context: context,
               token: "test-token",
               requester: requester
             )

    refute "repo_submit_change_proposal_review" in supported_tools
  end

  test "repo discussion excludes top-level comments that have typed response markers" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [
      %{"id" => 1, "body" => "Please update docs"},
      %{
        "id" => 2,
        "body" => "Addressed in latest push.\n\n<!-- symphony:response-to-pr-comment:1 -->"
      },
      %{"id" => 3, "body" => "Please add tests"}
    ])

    assert {:success,
            %{
              "data" => %{
                "discussion" => %{
                  "actionableItems" => [
                    %{
                      "kind" => "top_level_comment",
                      "commentId" => "3",
                      "responseAction" => %{
                        "prefilledArguments" => %{
                          "number" => "20",
                          "reply_to_comment_id" => "3"
                        },
                        "requiredArguments" => ["body"]
                      }
                    }
                  ],
                  "unresolvedFeedbackSummary" => %{
                    "unresolvedCount" => 1,
                    "unresolvedItems" => [%{"commentId" => "3"}]
                  },
                  "summary" => %{
                    "issueCommentCount" => 3,
                    "actionableTopLevelCommentCount" => 1,
                    "actionableFeedbackCount" => 1
                  }
                }
              }
            }} =
             DynamicTool.execute(repo_tool_context(), "repo_read_change_proposal_discussion", %{
               "number" => "20"
             })
  end

  test "repo top-level response marker canonicalizes rounded opaque provider ids" do
    Application.put_env(:symphony_elixir, :memory_repo_provider_issue_comments, [
      %{
        "id" => "2053484226757820416",
        "body" => "Please preserve the validation marker."
      }
    ])

    assert {:success,
            %{
              "data" => %{
                "action" => "comment_added",
                "comment" => %{
                  "body" => "Addressed in latest push.\n\n<!-- symphony:response-to-pr-comment:2053484226757820416 -->"
                }
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_add_change_proposal_comment",
               %{
                 "number" => "20",
                 "body" => "Addressed in latest push.",
                 "reply_to_comment_id" => "2053484226757820400"
               }
             )

    assert_received {:memory_repo_provider_pr_add_issue_comment, comment_opts}

    assert Keyword.fetch!(comment_opts, :body) ==
             "Addressed in latest push.\n\n<!-- symphony:response-to-pr-comment:2053484226757820416 -->"
  end

  test "repo review typed tools submit reviews add comments and reply to inline review comments" do
    assert {:success,
            %{
              "data" => %{
                "action" => "review_submitted",
                "review" => %{
                  "body" => "Please address this before merge.",
                  "state" => "request_changes"
                }
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_submit_change_proposal_review",
               %{
                 "number" => "20",
                 "event" => "request_changes",
                 "body" => "Please address this before merge."
               }
             )

    assert_received {:memory_repo_provider_pr_submit_review, review_opts}

    assert review_opts |> Keyword.take([:number, :event, :body]) |> Map.new() == %{
             number: "20",
             event: "request_changes",
             body: "Please address this before merge."
           }

    assert {:success,
            %{
              "data" => %{
                "action" => "comment_added",
                "comment" => %{
                  "body" => "Addressed in latest push.\n\n<!-- symphony:response-to-pr-comment:42 -->",
                  "id" => 1_000
                }
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_add_change_proposal_comment",
               %{
                 "number" => "20",
                 "body" => "Addressed in latest push.",
                 "reply_to_comment_id" => "42"
               }
             )

    assert_received {:memory_repo_provider_pr_add_issue_comment, comment_opts}

    assert comment_opts |> Keyword.take([:number, :body]) |> Map.new() == %{
             number: "20",
             body: "Addressed in latest push.\n\n<!-- symphony:response-to-pr-comment:42 -->"
           }

    assert {:success,
            %{
              "data" => %{
                "action" => "review_comment_replied",
                "comment" => %{
                  "body" => "Keeping this unchanged because the existing API is public.",
                  "in_reply_to_id" => "123"
                }
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_reply_change_proposal_review_comment",
               %{
                 "number" => "20",
                 "comment_id" => "123",
                 "body" => "Keeping this unchanged because the existing API is public."
               }
             )

    assert_received {:memory_repo_provider_pr_reply_review_comment, reply_opts}

    assert reply_opts |> Keyword.take([:number, :comment_id, :body]) |> Map.new() == %{
             number: "20",
             comment_id: "123",
             body: "Keeping this unchanged because the existing API is public."
           }
  end

  test "repo create-or-update tool creates proposals and applies labels through the provider facade" do
    assert {:success,
            %{
              "data" => %{
                "action" => "created",
                "changeProposal" => %{"url" => "https://example.com/pr/new"},
                "labels" => [%{"label" => "ready"}]
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-22 validation",
                 "body" => "Typed repo tool validation.",
                 "base" => "main",
                 "head" => "demo-22-validation",
                 "labels" => ["ready"]
               }
             )

    assert_received {:memory_repo_provider_pr_create, create_opts}

    assert create_opts |> Keyword.take([:title, :body, :base, :head]) |> Map.new() == %{
             title: "DEMO-22 validation",
             body: "Typed repo tool validation.",
             base: "main",
             head: "demo-22-validation"
           }

    assert_received {:memory_repo_provider_pr_add_label, label_opts}

    assert label_opts |> Keyword.take([:number, :label]) |> Map.new() == %{
             number: "https://example.com/pr/new",
             label: "ready"
           }
  end

  test "repo create-or-update create mode is idempotent across retry attempts" do
    assert {:success, %{"data" => %{"action" => "created"}}} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-30 retry validation",
                 "base" => "main",
                 "head" => "demo-30-retry-validation"
               }
             )

    assert_received {:memory_repo_provider_pr_create, _create_opts}

    Application.put_env(:symphony_elixir, :memory_repo_provider_pr, %{
      "number" => 30,
      "url" => "https://example.com/pr/30",
      "state" => "OPEN",
      "title" => "DEMO-30 retry validation",
      "headRefName" => "demo-30-retry-validation",
      "baseRefName" => "main"
    })

    assert {:success,
            %{
              "data" => %{
                "action" => "updated",
                "changeProposal" => %{"number" => 30, "url" => "https://example.com/pr/30"}
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-30 retry validation",
                 "base" => "main",
                 "head" => "demo-30-retry-validation"
               }
             )

    assert_received {:memory_repo_provider_pr_edit, edit_opts}

    assert edit_opts |> Keyword.take([:number, :title, :base]) |> Map.new() == %{
             number: "demo-30-retry-validation",
             title: "DEMO-30 retry validation",
             base: "main"
           }

    refute_received {:memory_repo_provider_pr_create, _duplicate_create_opts}
  end

  test "repo create-or-update tool generates a deterministic body when omitted" do
    assert {:success, %{"data" => %{"action" => "created"}}} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-26 validation",
                 "base" => "main",
                 "head" => "demo-26-validation"
               }
             )

    assert_received {:memory_repo_provider_pr_create, create_opts}
    assert create_opts[:body] =~ "DEMO-26 validation"
    assert create_opts[:body] =~ "Created by Symphony typed workflow tool."
    assert create_opts[:body] =~ "Base: main"
    assert create_opts[:body] =~ "Head: demo-26-validation"
  end

  test "repo create-or-update tool uses configured static body generator when body is omitted" do
    repo =
      memory_repo(%{
        change_proposal_body_generator: %{
          kind: "static",
          body: "Configured PR body."
        }
      })

    assert {:success, %{"data" => %{"action" => "created"}}} =
             DynamicTool.execute(
               repo_tool_context(repo),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-27 validation",
                 "base" => "main",
                 "head" => "demo-27-validation"
               }
             )

    assert_received {:memory_repo_provider_pr_create, create_opts}
    assert create_opts[:body] == "Configured PR body."
  end

  test "repo create-or-update tool renders configured template body generator" do
    repo =
      memory_repo(%{
        "change_proposal_body_generator" => %{
          "kind" => "template",
          "template" => "{{ title }}\n\nRepo: {{ repository }}\nProvider: {{ provider }}\nBase: {{ base }}\nHead: {{ head }}\nLabels: {{ labels }}"
        }
      })

    assert {:success, %{"data" => %{"action" => "created"}}} =
             DynamicTool.execute(
               repo_tool_context(repo),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-28 validation",
                 "base" => "main",
                 "head" => "demo-28-validation",
                 "labels" => ["ready", "typed-tool"]
               }
             )

    assert_received {:memory_repo_provider_pr_create, create_opts}

    assert create_opts[:body] ==
             """
             DEMO-28 validation

             Repo: acme/widgets
             Provider: memory
             Base: main
             Head: demo-28-validation
             Labels: ready, typed-tool
             """
             |> String.trim()
  end

  test "repo create-or-update tool rejects invalid configured body generator before provider create" do
    repo =
      memory_repo(%{
        change_proposal_body_generator: %{
          kind: "template",
          template: "{{ title }} {{ unknown }}"
        }
      })

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Invalid change proposal body generator: template uses unsupported placeholder(s): unknown."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(repo),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "DEMO-29 validation",
                 "base" => "main",
                 "head" => "demo-29-validation"
               }
             )

    refute_received {:memory_repo_provider_pr_create, _create_opts}
  end

  test "repo-provider typed tools resolve relative repo path from dynamic bridge workspace context" do
    workspace_root = Path.expand(SymphonyElixir.Config.settings!().workspace.root)

    root =
      Path.join(
        workspace_root,
        "symphony-repo-provider-dynamic-tool-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")

    File.mkdir_p!(repo_path)
    on_exit(fn -> File.rm_rf(root) end)

    context = repo_tool_context(github_repo("repo"))

    runner = fn
      "git", ["-C", ^repo_path, "branch", "--show-current"] ->
        {:ok, "feature/context-path\n"}

      "gh", ["pr", "view", "feature/context-path", "--repo", "acme/widgets", "--json", _fields] ->
        {:ok,
         Jason.encode!(%{
           "number" => 24,
           "url" => "https://github.com/acme/widgets/pull/24",
           "state" => "OPEN",
           "title" => "Typed provider tool validation"
         })}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:success,
            %{
              "data" => %{
                "changeProposal" => %{
                  "number" => 24,
                  "url" => "https://github.com/acme/widgets/pull/24"
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_change_proposal_snapshot",
               %{},
               workspace: root,
               command_runner: runner
             )
  end

  test "repo-provider typed tools resolve relative repo path from runtime target workspace context" do
    workspace_root = Path.expand(SymphonyElixir.Config.settings!().workspace.root)

    root =
      Path.join(
        workspace_root,
        "symphony-repo-provider-runtime-target-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")

    File.mkdir_p!(repo_path)
    on_exit(fn -> File.rm_rf(root) end)

    context = repo_tool_context(github_repo("repo"))
    target = Target.new(workspace_path: root)

    runner = fn
      "git", ["-C", ^repo_path, "branch", "--show-current"] ->
        {:ok, "feature/runtime-target\n"}

      "gh", ["pr", "view", "feature/runtime-target", "--repo", "acme/widgets", "--json", _fields] ->
        {:ok,
         Jason.encode!(%{
           "number" => 25,
           "url" => "https://github.com/acme/widgets/pull/25",
           "state" => "OPEN",
           "title" => "Typed provider runtime target validation"
         })}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:success,
            %{
              "data" => %{
                "changeProposal" => %{
                  "number" => 25,
                  "url" => "https://github.com/acme/widgets/pull/25"
                }
              }
            }} =
             DynamicTool.execute(
               context,
               "repo_change_proposal_snapshot",
               %{},
               agent_runtime_target: target,
               command_runner: runner
             )
  end

  test "repo-provider typed tools fail fast when relative repo path lacks workspace context" do
    context = repo_tool_context(github_repo("repo"))

    assert {:failure,
            %{
              "error" => %{
                "code" => "repo_provider_dynamic_tool_workspace_required",
                "message" => "Repo-provider dynamic tool requires workspace context to resolve relative repo path \"repo\".",
                "details" => %{"repo_path" => "repo", "source_kind" => "repo_provider"}
              }
            }} =
             DynamicTool.execute(context, "repo_change_proposal_snapshot", %{})
  end

  test "repo-provider typed tools reject invalid workspace context before provider calls" do
    workspace_root = Path.expand(SymphonyElixir.Config.settings!().workspace.root)

    invalid_workspace =
      Path.join(
        System.tmp_dir!(),
        "symphony-repo-provider-invalid-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_root)
    File.mkdir_p!(invalid_workspace)
    on_exit(fn -> File.rm_rf(invalid_workspace) end)

    context = repo_tool_context(github_repo("repo"))

    assert {:failure,
            %{
              "error" => %{
                "code" => "repo_provider_dynamic_tool_workspace_invalid",
                "message" => "Repo-provider dynamic tool received an invalid workspace context for relative repo path \"repo\".",
                "details" => %{
                  "repo_path" => "repo",
                  "source_kind" => "repo_provider",
                  "workspace_path" => ^invalid_workspace
                }
              }
            }} =
             DynamicTool.execute(context, "repo_change_proposal_snapshot", %{}, workspace: invalid_workspace)
  end

  test "dynamic tool bridge returns structured repo-provider workspace failures" do
    context = repo_tool_context(github_repo("repo"))

    assert %{
             "success" => false,
             "payload" => %{
               "error" => %{
                 "code" => "repo_provider_dynamic_tool_workspace_required",
                 "message" => "Repo-provider dynamic tool requires workspace context to resolve relative repo path \"repo\"."
               }
             }
           } =
             Bridge.execute("repo_change_proposal_snapshot", %{}, tool_context: context)
  end

  test "repo merge and close typed tools route through provider side-effect operations" do
    assert {:success, %{"data" => %{"action" => "merged", "changeProposal" => %{"target" => "20"}}}} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_merge_change_proposal",
               %{"number" => "20", "merge_style" => "squash"}
             )

    assert_received {:memory_repo_provider_pr_merge, merge_opts}

    assert merge_opts |> Keyword.take([:number, :merge_style]) |> Map.new() == %{
             number: "20",
             merge_style: "squash"
           }

    assert {:success, %{"data" => %{"action" => "closed", "changeProposal" => %{"target" => "20"}}}} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_close_change_proposal",
               %{"number" => "20", "comment" => "validation cleanup"}
             )

    assert_received {:memory_repo_provider_pr_close, close_opts}

    assert close_opts |> Keyword.take([:number, :comment]) |> Map.new() == %{
             number: "20",
             comment: "validation cleanup"
           }
  end

  test "repo typed tools return validation and provider failures as structured payloads" do
    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Creating a change proposal requires title."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{"mode" => "create", "body" => "missing title"}
             )

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Creating a change proposal requires base."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "Missing base",
                 "body" => "missing base",
                 "head" => "demo-missing-base"
               }
             )

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Creating a change proposal requires head, the source branch. Use head for create; branch is only for lookup/update."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "Missing head",
                 "body" => "missing head",
                 "base" => "main",
                 "branch" => "demo-missing-head"
               }
             )

    refute_received {:memory_repo_provider_pr_create, _missing_head_create_opts}

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Unsupported argument field(s): \"unexpected\"."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_create_or_update_change_proposal",
               %{
                 "mode" => "create",
                 "title" => "Unexpected field",
                 "body" => "unexpected field",
                 "base" => "main",
                 "head" => "demo-unexpected-field",
                 "unexpected" => true
               }
             )

    assert {:success, %{"data" => %{"exists" => false}}} =
             DynamicTool.execute(repo_tool_context(), "repo_change_proposal_snapshot", %{
               "number" => "20"
             })

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Missing required string field body."
              }
            }} =
             DynamicTool.execute(repo_tool_context(), "repo_add_change_proposal_comment", %{
               "number" => "20"
             })

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Missing required string field comment_id."
              }
            }} =
             DynamicTool.execute(
               repo_tool_context(),
               "repo_reply_change_proposal_review_comment",
               %{"number" => "20", "body" => "missing comment id"}
             )
  end

  defp repo_tool_context do
    repo_tool_context(memory_repo())
  end

  defp repo_tool_context(repo) do
    DynamicTool.capture_context(dynamic_tool_sources: [{SymphonyElixir.RepoProvider.DynamicToolSource, repo}])
  end

  defp memory_repo(options \\ %{}) do
    %{provider: %{kind: "memory", repository: "acme/widgets", options: options}}
  end

  defp github_repo(path) do
    %{path: path, provider: %{kind: "github", repository: "acme/widgets"}}
  end

  defp cnb_repo do
    %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: "https://api.cnb.example.test",
        web_base_url: "https://cnb.cool"
      }
    }
  end

  defp memory_pr do
    %{
      "number" => 20,
      "url" => "https://example.com/pr/20",
      "state" => "OPEN",
      "title" => "DEMO-20 validation",
      "headRefName" => "demo-20-validation",
      "baseRefName" => "main"
    }
  end
end
