defmodule SymphonyElixir.RepoProvider.CNBTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.RepoProvider.CNB.Adapter, as: CNB
  alias SymphonyElixir.RepoProvider.Error

  defmodule TestPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)
      {:ok, body, conn} = read_body(conn)

      send(opts[:owner], {:cnb_http_request, request_details(conn, body)})

      case {opts[:mode], conn.method, conn.request_path, conn.query_params} do
        {:success, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => "open"}} ->
          json(conn, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}])

        {:success, "PATCH", "/acme%2Fwidgets/-/pulls/42", _query} ->
          json(conn, 200, %{"number" => "42", "state" => "closed"})

        {{:patch_request_error, server_ref}, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => "open"}} ->
          conn = json(conn, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}])

          spawn(fn ->
            Process.sleep(10)

            case Agent.get(server_ref, & &1) do
              pid when is_pid(pid) -> Process.exit(pid, :shutdown)
              _other -> :ok
            end
          end)

          conn

        {{:patch_request_error, _server_ref}, "PATCH", "/acme%2Fwidgets/-/pulls/42", _query} ->
          Process.exit(self(), :kill)

        {:list_status_error, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => "open"}} ->
          json(conn, 500, %{"error" => "boom"})

        {:patch_status_error, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => "open"}} ->
          json(conn, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}])

        {:patch_status_error, "PATCH", "/acme%2Fwidgets/-/pulls/42", _query} ->
          json(conn, 500, %{"error" => "patch failed"})

        {{:auth_status_retry_then_success, counter_ref}, "GET", "/user", %{}} ->
          attempt =
            Agent.get_and_update(counter_ref, fn current ->
              next = current + 1
              {next, next}
            end)

          if attempt <= 2 do
            json(conn, 502, %{"error" => "try again"})
          else
            json(conn, 200, %{"username" => "retry-user"})
          end

        {{:patch_retry_guard, _counter_ref}, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => "open"}} ->
          json(conn, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}])

        {{:patch_retry_guard, counter_ref}, "PATCH", "/acme%2Fwidgets/-/pulls/42", _query} ->
          Agent.update(counter_ref, &(&1 + 1))
          json(conn, 500, %{"error" => "patch failed"})

        _other ->
          json(conn, 404, %{"error" => "not_found"})
      end
    end

    defp request_details(conn, body) do
      %{
        method: conn.method,
        path: conn.request_path,
        query: conn.query_params,
        headers: Map.new(conn.req_headers),
        body: body
      }
    end

    defp json(conn, status, payload) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end
  end

  test "validate_config rejects GitHub-only PR label enforcement and repository helpers cover config, opts, origin, and defaults" do
    assert :ok == CNB.validate_config(%{})
    assert :ok == CNB.validate_config(%{provider: %{options: %{required_pr_label: nil}}})

    assert {:error,
            %Error{
              code: :unsupported_option,
              provider: "cnb",
              operation: :validate_config
            }} =
             CNB.validate_config(%{provider: %{options: %{required_pr_label: "release-ready"}}})

    assert CNB.configured_repository(%{provider: %{repository: "acme/widgets"}}) == "acme/widgets"
    assert CNB.configured_repository(%{"provider" => %{"repository" => "string/widgets"}}) == "string/widgets"
    assert CNB.configured_repository(%{}) == nil

    assert {:ok, "opts/widgets"} = CNB.resolve_repository(%{}, repo: "opts/widgets")
    assert {:ok, "configured/widgets"} = CNB.resolve_repository(%{provider: %{repository: "configured/widgets"}})
    assert {:ok, "string/widgets"} = CNB.resolve_repository(%{"provider" => %{"repository" => "string/widgets"}})

    assert {:ok, "derived/widgets"} =
             CNB.resolve_repository(%{},
               command_runner: fn
                 "git", ["remote", "get-url", "origin"] ->
                   {:ok, "git@cnb.cool:derived/widgets.git\n"}
               end
             )

    with_temp_git_repo(fn repo_path ->
      assert {:ok, "configured-remote/widgets"} =
               CNB.resolve_repository(%{path: repo_path, remote: %{name: "upstream"}},
                 command_runner: fn
                   "git", ["-C", ^repo_path, "remote", "get-url", "upstream"] ->
                     {:ok, "git@cnb.cool:configured-remote/widgets.git\n"}
                 end
               )
    end)

    assert {:error, :missing_cnb_repository_slug} =
             CNB.resolve_repository(%{},
               command_runner: fn
                 "git", ["remote", "get-url", "origin"] -> {:error, {1, "boom"}}
               end
             )
  end

  test "uses configured repo path when resolving implicit CNB PR create head" do
    with_temp_git_repo(fn repo_path ->
      parent = self()

      repo = %{
        path: repo_path,
        base_branch: "main",
        provider: %{
          repository: "acme/widgets",
          api_base_url: "https://api.cnb.example.test",
          web_base_url: "https://cnb.example.test"
        }
      }

      requester = fn
        :post, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls", _headers, body ->
          send(parent, {:create_body, body})
          {:ok, 201, %{"number" => "42"}}
      end

      runner = fn
        "git", ["-C", ^repo_path, "branch", "--show-current"] ->
          {:ok, "feature/context-path\n"}

        command, args ->
          flunk("unexpected command: #{inspect({command, args})}")
      end

      assert {:ok, "https://cnb.example.test/acme/widgets/-/pulls/42"} =
               CNB.pr_create(repo,
                 title: "Open from configured repo path",
                 base: "main",
                 token: "test-token",
                 requester: requester,
                 command_runner: runner
               )

      assert_received {:create_body,
                       %{
                         "title" => "Open from configured repo path",
                         "base" => "main",
                         "head" => "feature/context-path"
                       }}
    end)
  end

  test "parses CNB repository slugs from HTTPS and SSH-style remotes" do
    assert CNB.parse_repository_slug("https://cnb.cool/acme/widgets.git") == "acme/widgets"
    assert CNB.parse_repository_slug("git@cnb.cool:acme/widgets.git") == "acme/widgets"
    assert CNB.parse_repository_slug(" https://cnb.cool/acme/widgets/sub.git ") == "acme/widgets/sub"
    assert CNB.parse_repository_slug("https://cnb.cool/acme.git") == nil
    assert CNB.parse_repository_slug("   ") == nil
    assert CNB.parse_repository_slug("https://github.com/acme/widgets.git") == nil
  end

  test "requires CNB token for close operations" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error, :missing_cnb_token} =
             CNB.close_open_pull_requests_for_branch(repo, "feature/cnb-provider")
  end

  test "lists and closes matching CNB pull requests for the branch" do
    repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: "https://api.cnb.example.test"
      }
    }

    parent = self()

    requester = fn
      :get, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", headers, nil ->
        send(parent, {:request, :get, headers})

        {:ok, 200,
         [
           %{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}},
           %{"number" => "7", "head" => %{"ref" => "refs/heads/other-branch"}}
         ]}

      :patch, "https://api.cnb.example.test/acme%2Fwidgets/-/pulls/42", _headers, %{state: "closed"} ->
        send(parent, {:request, :patch, "42"})
        {:ok, 200, %{"number" => "42", "state" => "closed"}}
    end

    assert :ok =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: requester,
               info: fn _message -> :ok end,
               error: fn _message -> :ok end
             )

    assert_received {:request, :get, headers}
    assert {"authorization", "Bearer test-token"} in headers
    assert_received {:request, :patch, "42"}
    refute_received {:request, :patch, "7"}
  end

  test "matches branch names without refs prefix and paginates CNB pull requests" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}
    parent = self()

    first_page =
      Enum.map(1..100, fn index ->
        %{
          "number" => Integer.to_string(index),
          "head" => %{"ref" => "refs/heads/other-#{index}"}
        }
      end)

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
        {:ok, 200, first_page}

      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=2&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
        {:ok, 200, [%{"number" => "200", "head" => %{"ref" => "refs/remotes/origin/feature/cnb-provider"}}]}

      :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/200", _headers, %{state: "closed"} ->
        send(parent, :paged_close)
        {:ok, 200, %{"number" => "200", "state" => "closed"}}
    end

    assert :ok =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: requester
             )

    assert_received :paged_close
  end

  test "ignores pulls without head refs and supports atom-key payloads" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}
    parent = self()

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
        {:ok, 200, [%{}, %{number: 200, head: %{ref: "refs/remotes/origin/feature/cnb-provider"}}]}

      :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/200", _headers, %{state: "closed"} ->
        send(parent, :atom_key_payload_closed)
        {:ok, 200, %{"number" => "200", "state" => "closed"}}
    end

    assert :ok =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               branch_head_ref: "feature/cnb-provider",
               requester: requester
             )

    assert_received :atom_key_payload_closed
  end

  test "normalizes CNB pr checks for the current pull" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?order_by=-updated_at&page=1&page_size=100&state=all", _headers, nil ->
        {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}]}

      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/commit-statuses", _headers, nil ->
        {:ok, 200,
         %{
           "state" => "success",
           "statuses" => [
             %{
               "context" => "ci",
               "state" => "success",
               "description" => "green",
               "created_at" => "2026-04-23T00:20:00Z",
               "updated_at" => "2026-04-23T00:21:00Z",
               "target_url" => "https://ci.example.test/runs/1"
             }
           ]
         }}
    end

    assert {:ok,
            [
              %{
                "name" => "ci",
                "status" => "completed",
                "conclusion" => "success",
                "summary" => "green",
                "details_url" => "https://ci.example.test/runs/1"
              }
            ]} =
             CNB.pr_checks(
               repo,
               token: "test-token",
               requester: requester,
               command_runner: fn
                 "git", ["branch", "--show-current"] -> {:ok, "feature/cnb-provider\n"}
               end
             )
  end

  test "uses overall CNB check state when no detailed statuses are present" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?order_by=-updated_at&page=1&page_size=100&state=all", _headers, nil ->
        {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}]}

      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/commit-statuses", _headers, nil ->
        {:ok, 200, %{"state" => "pending", "statuses" => []}}
    end

    assert {:ok,
            [
              %{
                "name" => "overall",
                "status" => "in_progress",
                "conclusion" => "pending",
                "summary" => "pending"
              }
            ]} =
             CNB.pr_checks(
               repo,
               token: "test-token",
               requester: requester,
               command_runner: fn
                 "git", ["branch", "--show-current"] -> {:ok, "feature/cnb-provider\n"}
               end
             )
  end

  test "pr_view normalizes merged CNB pulls to MERGED state" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:ok,
            %{
              "state" => "MERGED",
              "mergeable" => "MERGEABLE",
              "mergeStateStatus" => "CLEAN",
              "headRefName" => "feature/cnb-provider"
            }} =
             CNB.pr_view(repo,
               number: "42",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42", _headers, nil ->
                   {:ok, 200,
                    %{
                      "number" => "42",
                      "state" => "closed",
                      "title" => "Repo provider refactor",
                      "body" => "Merged by CNB",
                      "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"},
                      "base" => %{"ref" => "refs/heads/main"},
                      "mergeable_state" => "merged",
                      "merged_by" => %{"username" => "cnb"},
                      "blocked_on" => "unblocked",
                      "is_wip" => false
                    }}
               end
             )
  end

  test "pr_view accepts a full CNB pull request URL as the explicit target" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:ok,
            %{
              "number" => 42,
              "url" => "https://cnb.cool/acme/widgets/-/pulls/42",
              "state" => "OPEN"
            }} =
             CNB.pr_view(repo,
               number: "https://cnb.cool/acme/widgets/-/pulls/42",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42", _headers, nil ->
                   {:ok, 200,
                    %{
                      "number" => "42",
                      "state" => "open",
                      "title" => "Repo provider refactor",
                      "body" => "PR URL target",
                      "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"},
                      "base" => %{"ref" => "refs/heads/main"},
                      "mergeable_state" => "mergeable",
                      "blocked_on" => "unblocked",
                      "is_wip" => false
                    }}
               end
             )
  end

  test "pr_view rejects CNB pull request URLs for a different repository" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              code: :cnb_pull_target_repository_mismatch,
              details: %{
                target: "https://cnb.cool/acme/other/-/pulls/42",
                expected_repository: "acme/widgets",
                actual_repository: "acme/other"
              }
            }} =
             CNB.pr_view(repo,
               number: "https://cnb.cool/acme/other/-/pulls/42",
               token: "test-token",
               requester: fn _method, _url, _headers, _body ->
                 flunk("mismatched CNB PR URL should fail before HTTP")
               end
             )
  end

  test "pr_view keeps closed CNB pulls CLOSED when merged_by has no identity fields" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:ok,
            %{
              "state" => "CLOSED",
              "mergeable" => "MERGEABLE",
              "mergeStateStatus" => "CLEAN",
              "headRefName" => "feature/cnb-provider"
            }} =
             CNB.pr_view(repo,
               number: "7",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/7", _headers, nil ->
                   {:ok, 200,
                    %{
                      "number" => "7",
                      "state" => "closed",
                      "title" => "Repo provider probe",
                      "body" => "Closed without merge",
                      "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"},
                      "base" => %{"ref" => "refs/heads/main"},
                      "mergeable_state" => "mergeable",
                      "merged_by" => %{"is_npc" => false},
                      "blocked_on" => "unblocked",
                      "is_wip" => false
                    }}
               end
             )
  end

  test "run_list surfaces actionable errors when CNB build scope is missing" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error,
            %SymphonyElixir.RepoProvider.Error{
              code: :cnb_build_scope_required,
              message: message
            }} =
             CNB.run_list(repo,
               branch: "feature/cnb-provider",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?order_by=-updated_at&page=1&page_size=100&state=all", _headers, nil ->
                   {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"}}]}

                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/build/logs?page=1&page_size=20&sha=abc123&sourceRef=feature%2Fcnb-provider", _headers, nil ->
                   {:error,
                    {:cnb_api_status, :get, "https://api.cnb.cool/acme%2Fwidgets/-/build/logs?page=1&page_size=20&sha=abc123&sourceRef=feature%2Fcnb-provider", 403,
                     %{"errcode" => 7, "errmsg" => "The bill authorization scope cannot access the current request."}}}
               end
             )

    assert message =~ "Grant CNB build authorization"
  end

  test "run_view surfaces actionable errors when CNB build status scope is missing" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error,
            %SymphonyElixir.RepoProvider.Error{
              code: :cnb_build_scope_required,
              message: message
            }} =
             CNB.run_view(repo,
               run_id: "1001",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/build/logs?page=1&page_size=1&sn=1001", _headers, nil ->
                   {:ok, 200,
                    %{
                      "data" => [
                        %{
                          "buildLogUrl" => "https://cnb.cool/acme/widgets/-/build/logs/1001",
                          "sha" => "abc123",
                          "slug" => "acme/widgets",
                          "sn" => "1001",
                          "sourceRef" => "feature/cnb-provider",
                          "status" => "success",
                          "title" => "CI"
                        }
                      ]
                    }}

                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/build/status/1001", _headers, nil ->
                   {:error,
                    {:cnb_api_status, :get, "https://api.cnb.cool/acme%2Fwidgets/-/build/status/1001", 403,
                     %{"errcode" => 7, "errmsg" => "The bill authorization scope cannot access the current request."}}}
               end
             )

    assert message =~ "Grant CNB build authorization"
  end

  test "translates CNB api issue comments and direct API calls" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}
    parent = self()

    requester = fn
      :get, url, headers, nil when is_binary(url) ->
        cond do
          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/comments?") ->
            send(parent, {:headers, headers})

            query = URI.decode_query(URI.parse(url).query || "")
            assert query["page"] == "1"
            assert query["page_size"] == "5"
            assert query["sort"] == "created"

            {:ok, 200,
             [
               %{
                 "id" => "55",
                 "body" => "top-level note",
                 "created_at" => "2026-04-23T00:25:00Z",
                 "updated_at" => "2026-04-23T00:26:00Z",
                 "author" => %{"username" => "reviewer"}
               }
             ]}

          true ->
            flunk("unexpected GET url: #{url}")
        end

      :post, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/comments", _headers, %{"body" => "reply", "work_mode" => true} ->
        {:ok, 201,
         %{
           "id" => "56",
           "body" => "reply",
           "author" => %{"username" => "codex", "is_npc" => true}
         }}

      :patch, "https://api.cnb.cool/custom/endpoint", _headers, %{"name" => "value"} ->
        {:ok, 200, %{"ok" => true}}
    end

    assert {:ok,
            [
              %{
                "id" => "55",
                "body" => "top-level note",
                "user" => %{"login" => "reviewer", "type" => "User"}
              }
            ]} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/{owner}/{repo}/issues/42/comments",
               method: "GET",
               fields: %{"page" => "1", "per_page" => "5", "sort" => "created"}
             )

    assert_received {:headers, headers}
    assert {"authorization", "Bearer test-token"} in headers

    assert {:ok,
            %{
              "id" => "56",
              "body" => "reply",
              "user" => %{"login" => "codex", "type" => "Bot"}
            }} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/acme/widgets/issues/42/comments",
               method: "POST",
               fields: %{"body" => "reply", "work_mode" => "true"}
             )

    assert {:ok, %{"ok" => true}} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "/custom/endpoint",
               method: "PATCH",
               fields: %{"name" => "value"}
             )
  end

  test "lists CNB issue comments across pages and adds top-level issue comments through dedicated commands" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => Integer.to_string(id),
          "body" => "top-level note #{id}",
          "created_at" => "2026-04-23T00:10:00Z",
          "updated_at" => "2026-04-23T00:10:00Z",
          "author" => %{"username" => "reviewer"}
        }
      end)

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          url == "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200, %{"number" => "42"}}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/comments?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200, page_one}

              "2" ->
                {:ok, 200, [%{"id" => "101", "body" => "top-level note 101", "author" => %{"username" => "reviewer"}}]}

              "3" ->
                {:ok, 200, []}
            end

          true ->
            flunk("unexpected GET url: #{url}")
        end

      :post, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/comments", _headers, %{"body" => "[codex] acknowledged"} ->
        {:ok, 201,
         %{
           "id" => "102",
           "body" => "[codex] acknowledged",
           "author" => %{"username" => "codex"}
         }}
    end

    assert {:ok, comments} =
             CNB.pr_issue_comments(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )

    assert length(comments) == 101
    ids = Enum.map(comments, & &1["id"])
    assert Enum.member?(ids, "1")
    assert Enum.member?(ids, "101")

    assert {:ok,
            %{
              "id" => "102",
              "body" => "[codex] acknowledged",
              "user" => %{"login" => "codex", "type" => "User"}
            }} =
             CNB.pr_add_issue_comment(repo,
               token: "test-token",
               requester: requester,
               number: "42",
               body: "[codex] acknowledged"
             )
  end

  test "validates CNB issue comment inputs before making requests" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error,
            %Error{
              exit_code: 64,
              message: "CNB pr-add-issue-comment requires a non-empty body"
            }} =
             CNB.pr_add_issue_comment(repo,
               token: "test-token",
               body: "",
               requester: fn _method, _url, _headers, _body ->
                 flunk("CNB issue comment requests should not run without a body")
               end
             )
  end

  test "translates explicit CNB api repo endpoints with nested repository paths" do
    repo = %{provider: %{kind: "cnb", repository: "unused/widgets"}}
    parent = self()

    requester = fn
      :get, url, headers, nil when is_binary(url) ->
        if String.starts_with?(url, "https://api.cnb.cool/example-org%2FAI%2Fsample-cnb-project/-/pulls/42/comments?") do
          send(parent, {:headers, headers})

          query = URI.decode_query(URI.parse(url).query || "")
          assert query["page"] == "1"
          assert query["page_size"] == "2"

          {:ok, 200,
           [
             %{
               "id" => "77",
               "body" => "nested repo path works",
               "author" => %{"username" => "reviewer"}
             }
           ]}
        else
          flunk("unexpected GET url: #{url}")
        end
    end

    assert {:ok, [%{"id" => "77", "body" => "nested repo path works"}]} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/example-org/AI/sample-cnb-project/issues/42/comments",
               method: "GET",
               fields: %{"page" => "1", "per_page" => "2"}
             )

    assert_received {:headers, headers}
    assert {"authorization", "Bearer test-token"} in headers
  end

  test "translates CNB api review comments and check runs" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200,
                 [
                   %{
                     "id" => "9",
                     "state" => "approved",
                     "body" => "looks good",
                     "created_at" => "2026-04-23T00:00:00Z",
                     "updated_at" => "2026-04-23T00:05:00Z",
                     "author" => %{"username" => "reviewer"}
                   }
                 ]}

              "2" ->
                {:ok, 200, []}
            end

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/9/comments?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200,
                 [
                   %{
                     "id" => "101",
                     "review_id" => "9",
                     "reply_to_comment_id" => nil,
                     "body" => "inline note",
                     "created_at" => "2026-04-23T00:10:00Z",
                     "updated_at" => "2026-04-23T00:10:00Z",
                     "author" => %{"username" => "reviewer"},
                     "path" => "lib/example.ex",
                     "commit_hash" => "abc123"
                   }
                 ]}

              "2" ->
                {:ok, 200, []}
            end

          String.contains?(url, "/-/pulls?") and String.contains?(url, "state=all") ->
            {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"}}]}

          String.ends_with?(url, "/-/pulls/42/commit-statuses") ->
            {:ok, 200,
             %{
               "state" => "success",
               "statuses" => [
                 %{
                   "context" => "ci",
                   "state" => "success",
                   "description" => "green",
                   "created_at" => "2026-04-23T00:20:00Z",
                   "updated_at" => "2026-04-23T00:21:00Z"
                 }
               ]
             }}

          true ->
            flunk("unexpected GET url: #{url}")
        end

      :post,
      "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/9/replies",
      _headers,
      %{
        "body" => "reply",
        "reply_to_comment_id" => "101"
      } ->
        {:ok, 201,
         %{
           "id" => "102",
           "review_id" => "9",
           "reply_to_comment_id" => "101",
           "body" => "reply",
           "author" => %{"username" => "codex"}
         }}
    end

    assert {:ok,
            [
              %{
                "id" => "101",
                "pull_request_review_id" => "9",
                "path" => "lib/example.ex",
                "commit_id" => "abc123"
              }
            ]} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/{owner}/{repo}/pulls/42/comments",
               method: "GET"
             )

    assert {:ok, %{"id" => "102", "in_reply_to_id" => "101", "body" => "reply"}} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/{owner}/{repo}/pulls/42/comments",
               method: "POST",
               fields: %{"body" => "reply", "in_reply_to" => "101"}
             )

    assert {:ok, %{"total_count" => 1, "check_runs" => [%{"name" => "ci", "conclusion" => "success"}]}} =
             CNB.api(repo,
               token: "test-token",
               requester: requester,
               endpoint: "repos/{owner}/{repo}/commits/abc123/check-runs",
               method: "GET"
             )
  end

  test "lists and replies to CNB review comments through dedicated commands" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          url == "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200, %{"number" => "42"}}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200, [%{"id" => "9", "state" => "approved", "author" => %{"username" => "reviewer"}}]}

              "2" ->
                {:ok, 200, []}
            end

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/9/comments?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200,
                 [
                   %{
                     "id" => "101",
                     "review_id" => "9",
                     "reply_to_comment_id" => nil,
                     "body" => "inline note",
                     "author" => %{"username" => "reviewer"},
                     "path" => "lib/example.ex",
                     "commit_hash" => "abc123"
                   }
                 ]}

              "2" ->
                {:ok, 200, []}
            end

          true ->
            flunk("unexpected GET url: #{url}")
        end

      :post, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/9/replies", _headers, %{"body" => "[codex] acknowledged", "reply_to_comment_id" => "101"} ->
        {:ok, 201,
         %{
           "id" => "102",
           "review_id" => "9",
           "reply_to_comment_id" => "101",
           "body" => "[codex] acknowledged",
           "author" => %{"username" => "codex"}
         }}
    end

    assert {:ok,
            [
              %{
                "id" => "101",
                "body" => "inline note",
                "path" => "lib/example.ex",
                "commit_id" => "abc123",
                "pull_request_review_id" => "9"
              }
            ]} =
             CNB.pr_review_comments(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )

    assert {:ok, %{"id" => "102", "in_reply_to_id" => "101", "body" => "[codex] acknowledged"}} =
             CNB.pr_reply_review_comment(repo,
               token: "test-token",
               requester: requester,
               number: "42",
               comment_id: "101",
               body: "[codex] acknowledged"
             )
  end

  test "normalizes CNB opaque comment ids as strings and treats reply id zero as top-level" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}
    review_id = "2053482086874247168"
    comment_id = "2053482086874247168"

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42", _headers, nil ->
        {:ok, 200, %{"number" => "42"}}

      :get, url, _headers, nil when is_binary(url) ->
        cond do
          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            {:ok, 200, [%{"id" => review_id, "state" => "commented", "author" => %{"username" => "reviewer"}}]}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/#{review_id}/comments?") ->
            {:ok, 200,
             [
               %{
                 "id" => comment_id,
                 "review_id" => review_id,
                 "reply_to_comment_id" => "0",
                 "body" => "inline note",
                 "author" => %{"username" => "reviewer"},
                 "path" => "lib/example.ex",
                 "commit_hash" => "abc123"
               }
             ]}

          true ->
            flunk("unexpected GET url: #{url}")
        end
    end

    assert {:ok,
            [
              %{
                "id" => ^comment_id,
                "in_reply_to_id" => nil,
                "pull_request_review_id" => ^review_id
              }
            ]} =
             CNB.pr_review_comments(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )
  end

  test "lists CNB reviews through the dedicated pr-reviews command" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          url == "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200, %{"number" => "42"}}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200,
                 [
                   %{
                     "id" => "9",
                     "state" => "approved",
                     "body" => "looks good",
                     "created_at" => "2026-04-23T00:00:00Z",
                     "updated_at" => "2026-04-23T00:05:00Z",
                     "author" => %{"username" => "reviewer"}
                   }
                 ]}

              "2" ->
                {:ok, 200, []}
            end

          true ->
            flunk("unexpected GET url: #{url}")
        end
    end

    assert {:ok,
            [
              %{
                "id" => "9",
                "body" => "looks good",
                "state" => "APPROVED",
                "user" => %{"login" => "reviewer", "type" => "User"}
              }
            ]} =
             CNB.pr_reviews(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )
  end

  test "returns all CNB reviews by default across pages" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => Integer.to_string(id),
          "state" => "commented",
          "body" => "review #{id}",
          "created_at" => "2026-04-23T00:00:00Z",
          "updated_at" => "2026-04-23T00:05:00Z",
          "author" => %{"username" => "reviewer-#{id}"}
        }
      end)

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          url == "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200, %{"number" => "42"}}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" -> {:ok, 200, page_one}
              "2" -> {:ok, 200, [%{"id" => "101", "state" => "approved", "author" => %{"username" => "reviewer-101"}}]}
              "3" -> {:ok, 200, []}
            end

          true ->
            flunk("unexpected GET url: #{url}")
        end
    end

    assert {:ok, reviews} =
             CNB.pr_reviews(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )

    assert length(reviews) == 101
    ids = Enum.map(reviews, & &1["id"])
    assert Enum.member?(ids, "1")
    assert Enum.member?(ids, "101")
    assert List.last(reviews)["state"] == "APPROVED"
  end

  test "returns all CNB review comments by default across pages" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    page_one =
      Enum.map(1..100, fn id ->
        %{
          "id" => Integer.to_string(id),
          "review_id" => "9",
          "reply_to_comment_id" => nil,
          "body" => "inline note #{id}",
          "author" => %{"username" => "reviewer"},
          "path" => "lib/example.ex",
          "commit_hash" => "abc123"
        }
      end)

    requester = fn
      :get, url, _headers, nil when is_binary(url) ->
        cond do
          url == "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42" ->
            {:ok, 200, %{"number" => "42"}}

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" ->
                {:ok, 200, [%{"id" => "9", "state" => "approved", "author" => %{"username" => "reviewer"}}]}

              "2" ->
                {:ok, 200, []}
            end

          String.starts_with?(url, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42/reviews/9/comments?") ->
            query = URI.decode_query(URI.parse(url).query || "")

            case query["page"] do
              "1" -> {:ok, 200, page_one}
              "2" -> {:ok, 200, [%{"id" => "101", "review_id" => "9", "body" => "inline note 101", "author" => %{"username" => "reviewer"}}]}
              "3" -> {:ok, 200, []}
            end

          true ->
            flunk("unexpected GET url: #{url}")
        end
    end

    assert {:ok, comments} =
             CNB.pr_review_comments(repo,
               token: "test-token",
               requester: requester,
               number: "42"
             )

    assert length(comments) == 101
    ids = Enum.map(comments, & &1["id"])
    assert Enum.member?(ids, "1")
    assert Enum.member?(ids, "101")
  end

  test "returns ok when branch head ref filter is blank" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert :ok =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               branch_head_ref: "",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
                   {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}]}
               end
             )
  end

  test "returns the first close error and logs partial success summaries" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}
    parent = self()

    requester = fn
      :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
        {:ok, 200,
         [
           %{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}},
           %{"number" => "43", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}
         ]}

      :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42", _headers, %{state: "closed"} ->
        {:ok, 200, %{"number" => "42", "state" => "closed"}}

      :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/43", _headers, %{state: "closed"} ->
        {:error, {:cnb_api_request, :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/43", :boom}}
    end

    assert {:error, {:cnb_api_request, :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/43", :boom}} =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: requester,
               info: fn message -> send(parent, {:info, message}) end,
               error: fn message -> send(parent, {:error, message}) end
             )

    assert_received {:info, "Closed 1 CNB PR(s) for branch feature/cnb-provider"}

    assert_received {:error, "Failed to close CNB PRs for branch feature/cnb-provider: {:cnb_api_request, :patch, \"https://api.cnb.cool/acme%2Fwidgets/-/pulls/43\", :boom}"}
  end

  test "surfaces missing pull numbers and unknown list payloads" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error, {:cnb_unknown_payload, :missing_pull_number}} =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
                   {:ok, 200, [%{"head" => %{"ref" => "refs/heads/feature/cnb-provider"}}]}
               end
             )

    assert {:error, {:cnb_unknown_payload, :list_pulls, %{"pulls" => []}}} =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
                   {:ok, 200, %{"pulls" => []}}
               end
             )
  end

  test "surfaces request errors from list and close requests" do
    repo = %{provider: %{kind: "cnb", repository: "acme/widgets"}}

    assert {:error, {:cnb_api_request, :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", :econnrefused}} =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
                   {:error, {:cnb_api_request, :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", :econnrefused}}
               end
             )

    assert {:error, {:cnb_unknown_payload, :close_pull, %{"unexpected" => true}}} =
             CNB.close_open_pull_requests_for_branch(
               repo,
               "feature/cnb-provider",
               token: "test-token",
               requester: fn
                 :get, "https://api.cnb.cool/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at", _headers, nil ->
                   {:ok, 200, [%{"number" => "42", "head" => %{"ref" => "refs/heads/feature/cnb-provider"}}]}

                 :patch, "https://api.cnb.cool/acme%2Fwidgets/-/pulls/42", _headers, %{state: "closed"} ->
                   {:ok, 500, %{"unexpected" => true}}
               end
             )
  end

  test "uses the default requester for successful close operations" do
    api_base_url = start_test_server!(:success)

    repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: api_base_url
      }
    }

    assert :ok ==
             CNB.close_open_pull_requests_for_branch(repo, "feature/cnb-provider", token: "test-token")

    assert_received {:cnb_http_request, %{method: "GET", path: "/acme%2Fwidgets/-/pulls", headers: headers}}
    assert headers["authorization"] == "Bearer test-token"

    assert_received {:cnb_http_request, %{method: "PATCH", path: "/acme%2Fwidgets/-/pulls/42", body: body}}
    assert Jason.decode!(body) == %{"state" => "closed"}
  end

  test "passes runtime timeout and retry options to arity-5 requesters" do
    repo = %{
      provider: %{kind: "cnb"},
      runtime: %{
        http_timeout_seconds: "12",
        max_http_retries: "2",
        retry_backoff_seconds: "0"
      }
    }

    requester = fn
      :get, "https://api.cnb.cool/user", _headers, nil, request_opts ->
        assert request_opts.timeout_ms == 12_000
        assert request_opts.retry_delays_ms == [0, 0]
        {:ok, 200, %{"username" => "cnb.runtime"}}
    end

    assert {:ok, "CNB auth ok as cnb.runtime"} =
             CNB.auth_status(repo, token: "test-token", requester: requester)
  end

  test "default requester retries retryable GET auth requests" do
    counter_ref = start_supervised!({Agent, fn -> 0 end})
    api_base_url = start_test_server!({:auth_status_retry_then_success, counter_ref})

    repo = %{
      provider: %{
        kind: "cnb",
        api_base_url: api_base_url
      },
      runtime: %{
        http_timeout_seconds: 1,
        max_http_retries: 2,
        retry_backoff_seconds: 0
      }
    }

    assert {:ok, "CNB auth ok as retry-user"} = CNB.auth_status(repo, token: "test-token")
    assert Agent.get(counter_ref, & &1) == 3
  end

  test "default requester does not retry mutating CNB requests" do
    counter_ref = start_supervised!({Agent, fn -> 0 end})
    api_base_url = start_test_server!({:patch_retry_guard, counter_ref})

    repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: api_base_url
      },
      runtime: %{
        http_timeout_seconds: 1,
        max_http_retries: 5,
        retry_backoff_seconds: 0
      }
    }

    assert {:error, {:cnb_api_status, :patch, _url, 500, %{"error" => "patch failed"}}} =
             CNB.close_open_pull_requests_for_branch(repo, "feature/cnb-provider", token: "test-token")

    assert Agent.get(counter_ref, & &1) == 1
  end

  test "surfaces default requester status failures for list and close calls" do
    list_api_base_url = start_test_server!(:list_status_error)

    list_repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: list_api_base_url
      },
      runtime: %{
        max_http_retries: 0,
        retry_backoff_seconds: 0
      }
    }

    assert {:error, {:cnb_api_status, :get, url, 500, %{"error" => "boom"}}} =
             CNB.close_open_pull_requests_for_branch(list_repo, "feature/cnb-provider", token: "test-token")

    assert url =~ "/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at"

    patch_api_base_url = start_test_server!(:patch_status_error)

    patch_repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: patch_api_base_url
      },
      runtime: %{
        max_http_retries: 0,
        retry_backoff_seconds: 0
      }
    }

    assert {:error, {:cnb_api_status, :patch, patch_url, 500, %{"error" => "patch failed"}}} =
             CNB.close_open_pull_requests_for_branch(patch_repo, "feature/cnb-provider", token: "test-token")

    assert patch_url =~ "/acme%2Fwidgets/-/pulls/42"
  end

  test "surfaces default requester transport failures for list and close calls" do
    list_repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: "http://127.0.0.1:1"
      },
      runtime: %{
        max_http_retries: 0,
        retry_backoff_seconds: 0
      }
    }

    assert {:error, {:cnb_api_request, :get, url, _reason}} =
             CNB.close_open_pull_requests_for_branch(list_repo, "feature/cnb-provider", token: "test-token")

    assert url =~ "/acme%2Fwidgets/-/pulls?page=1&page_size=100&state=open&order_by=-updated_at"

    patch_api_base_url = start_test_server!(:patch_request_error)

    patch_repo = %{
      provider: %{
        kind: "cnb",
        repository: "acme/widgets",
        api_base_url: patch_api_base_url
      },
      runtime: %{
        max_http_retries: 0,
        retry_backoff_seconds: 0
      }
    }

    assert {:error, {:cnb_api_request, :patch, patch_url, _reason}} =
             CNB.close_open_pull_requests_for_branch(patch_repo, "feature/cnb-provider", token: "test-token")

    assert patch_url =~ "/acme%2Fwidgets/-/pulls/42"
  end

  test "can resolve the repository from a real git origin remote" do
    with_temp_git_repo(fn root ->
      {_, 0} = CommandEnv.system_cmd("git", ["remote", "add", "origin", "https://cnb.cool/acme/widgets.git"], cd: root)

      previous_cwd = File.cwd!()

      try do
        File.cd!(root)
        assert {:ok, "acme/widgets"} = CNB.resolve_repository(%{})
      after
        File.cd!(previous_cwd)
      end
    end)
  end

  test "returns missing repository when default git lookup fails" do
    with_temp_git_repo(fn root ->
      previous_cwd = File.cwd!()

      try do
        File.cd!(root)
        assert {:error, :missing_cnb_repository_slug} = CNB.resolve_repository(%{})
      after
        File.cd!(previous_cwd)
      end
    end)
  end

  test "returns missing repository when git is unavailable on PATH" do
    with_empty_path(fn ->
      assert {:error, :missing_cnb_repository_slug} = CNB.resolve_repository(%{})
    end)
  end

  defp start_test_server!(mode) do
    mode = normalize_server_mode(mode)

    pid =
      start_supervised!({Bandit, plug: {TestPlug, owner: self(), mode: mode}, scheme: :http, port: 0, ip: {127, 0, 0, 1}})

    maybe_store_server_pid(mode, pid)
    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp with_temp_git_repo(fun) do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "cnb-repo-provider-test-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      {_, 0} = CommandEnv.system_cmd("git", ["init", "--initial-branch=main"], cd: root)
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp with_empty_path(fun) do
    previous_path = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      fun.()
    after
      case previous_path do
        nil -> System.delete_env("PATH")
        value -> System.put_env("PATH", value)
      end
    end
  end

  defp normalize_server_mode(:patch_request_error) do
    server_ref = start_supervised!({Agent, fn -> nil end})
    {:patch_request_error, server_ref}
  end

  defp normalize_server_mode(mode), do: mode

  defp maybe_store_server_pid({:patch_request_error, server_ref}, pid) do
    Agent.update(server_ref, fn _current -> pid end)
  end

  defp maybe_store_server_pid(_mode, _pid), do: :ok
end
