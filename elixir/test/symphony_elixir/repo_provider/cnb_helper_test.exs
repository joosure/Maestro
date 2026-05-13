defmodule SymphonyElixir.RepoProvider.CNBHelperTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.TestSupport.Snapshot
  alias SymphonyElixir.Workspace.AutomationPack

  defmodule TestPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)
      {:ok, body, conn} = read_body(conn)

      send(opts[:owner], {:cnb_request, request_details(conn, body)})

      {repo, tail} = split_repo_path(conn.path_info)

      handle_request(
        conn,
        body,
        conn.method,
        repo,
        tail,
        conn.query_params,
        opts[:mode] || :success
      )
    end

    defp handle_request(
           conn,
           _body,
           "GET",
           nil,
           ["user"],
           _query,
           {:user_status_once, counter, status}
         ) do
      current =
        Agent.get_and_update(counter, fn attempts ->
          {attempts, attempts + 1}
        end)

      if current == 0 do
        conn
        |> put_resp_header("retry-after", "0")
        |> json(status, %{"error" => "retry_me"})
      else
        json(conn, 200, %{"username" => "tester"})
      end
    end

    defp handle_request(conn, _body, "GET", nil, ["user"], _query, {:sleep_user, delay_ms}) do
      Process.sleep(delay_ms)
      json(conn, 200, %{"username" => "tester"})
    end

    defp handle_request(conn, _body, "GET", nil, ["user"], _query, _mode) do
      json(conn, 200, %{"username" => "tester"})
    end

    defp handle_request(conn, body, method, "acme/widgets", tail, query, mode) do
      case handle_pull_request(conn, body, method, tail, query) do
        {:unhandled, conn} ->
          case handle_build_request(conn, method, tail, query, mode) do
            {:unhandled, conn} ->
              case handle_issue_request(conn, body, method, tail, query) do
                {:unhandled, conn} -> json(conn, 404, %{"error" => "not_found"})
                response -> response
              end

            response ->
              response
          end

        response ->
          response
      end
    end

    defp handle_request(conn, _body, _method, _repo, _tail, _query, _mode) do
      json(conn, 404, %{"error" => "not_found"})
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls"], %{"page" => "1"}) do
      json(conn, 200, pull_list())
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls"], _query) do
      json(conn, 200, [])
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42"], _query) do
      json(conn, 200, current_pull())
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42", "comments"], _query) do
      json(conn, 200, issue_comments())
    end

    defp handle_pull_request(conn, body, "POST", ["pulls", "42", "comments"], _query) do
      payload = Jason.decode!(body)

      json(conn, 201, %{
        "id" => "88",
        "body" => payload["body"],
        "created_at" => "2026-04-23T00:30:00Z",
        "updated_at" => "2026-04-23T00:30:00Z",
        "author" => %{"username" => "codex"}
      })
    end

    defp handle_pull_request(conn, _body, "POST", ["pulls"], _query) do
      json(conn, 201, %{"number" => "42"})
    end

    defp handle_pull_request(conn, _body, "PATCH", ["pulls", "42"], _query) do
      json(conn, 200, %{"number" => "42"})
    end

    defp handle_pull_request(conn, _body, "PUT", ["pulls", "42", "merge"], _query) do
      json(conn, 200, %{"number" => "42"})
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42", "reviews"], %{
           "page" => "1",
           "page_size" => "100"
         }) do
      json(conn, 200, reviews())
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42", "reviews"], _query) do
      json(conn, 200, [])
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42", "reviews", "9", "comments"], %{
           "page" => "1",
           "page_size" => "100"
         }) do
      json(conn, 200, review_comments())
    end

    defp handle_pull_request(
           conn,
           _body,
           "GET",
           ["pulls", "42", "reviews", "9", "comments"],
           _query
         ) do
      json(conn, 200, [])
    end

    defp handle_pull_request(
           conn,
           body,
           "POST",
           ["pulls", "42", "reviews", "9", "replies"],
           _query
         ) do
      payload = Jason.decode!(body)

      json(conn, 201, %{
        "id" => "102",
        "review_id" => "9",
        "reply_to_comment_id" => payload["reply_to_comment_id"],
        "body" => payload["body"],
        "created_at" => "2026-04-23T01:00:00Z",
        "updated_at" => "2026-04-23T01:00:00Z",
        "author" => %{"username" => "codex"}
      })
    end

    defp handle_pull_request(conn, _body, "GET", ["pulls", "42", "commit-statuses"], _query) do
      json(conn, 200, commit_statuses())
    end

    defp handle_pull_request(conn, _body, _method, _tail, _query) do
      {:unhandled, conn}
    end

    defp handle_build_request(conn, "GET", ["build", "logs"], _query, :build_scope_forbidden) do
      json(conn, 403, %{
        "errcode" => 7,
        "errmsg" => "The bill authorization scope cannot access the current request."
      })
    end

    defp handle_build_request(
           conn,
           "GET",
           ["build", "status", _run_id],
           _query,
           :build_scope_forbidden
         ) do
      json(conn, 403, %{
        "errcode" => 7,
        "errmsg" => "The bill authorization scope cannot access the current request."
      })
    end

    defp handle_build_request(conn, "GET", ["build", "logs"], %{"sn" => "1001"}, _mode) do
      json(conn, 200, build_logs(sn: "1001"))
    end

    defp handle_build_request(
           conn,
           "GET",
           ["build", "logs"],
           %{"sourceRef" => "feature/cnb-provider", "sha" => "abc123"},
           _mode
         ) do
      json(conn, 200, build_logs())
    end

    defp handle_build_request(conn, "GET", ["build", "status", "1001"], _query, _mode) do
      json(conn, 200, build_status())
    end

    defp handle_build_request(
           conn,
           "GET",
           ["build", "logs", "stage", "1001", "pipeline-1", "stage-1"],
           _query,
           _mode
         ) do
      json(conn, 200, build_stage("stage-1", "checkout", ["cloning repo", "checkout complete"]))
    end

    defp handle_build_request(
           conn,
           "GET",
           ["build", "logs", "stage", "1001", "pipeline-1", "stage-2"],
           _query,
           _mode
         ) do
      json(conn, 200, build_stage("stage-2", "test", ["mix test", "80 tests, 0 failures"]))
    end

    defp handle_build_request(conn, _method, _tail, _query, _mode) do
      {:unhandled, conn}
    end

    defp handle_issue_request(conn, _body, "GET", ["issues", "42", "comments"], _query) do
      json(conn, 200, issue_comments())
    end

    defp handle_issue_request(conn, body, "POST", ["issues", "42", "comments"], _query) do
      payload = Jason.decode!(body)

      json(conn, 201, %{
        "id" => "88",
        "body" => payload["body"],
        "created_at" => "2026-04-23T00:30:00Z",
        "updated_at" => "2026-04-23T00:30:00Z",
        "author" => %{"username" => "codex"}
      })
    end

    defp handle_issue_request(conn, _body, _method, _tail, _query) do
      {:unhandled, conn}
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

    defp split_repo_path(["user"]), do: {nil, ["user"]}

    defp split_repo_path(path_info) do
      case Enum.split_while(path_info, &(&1 != "-")) do
        {repo_segments, ["-" | tail]} ->
          {repo_segments |> Enum.join("/") |> URI.decode(), tail}

        {_repo_segments, tail} ->
          {nil, tail}
      end
    end

    defp json(conn, status, payload) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end

    defp pull_list do
      [
        current_pull(),
        %{
          "number" => "7",
          "state" => "merged",
          "title" => "Old PR",
          "body" => "",
          "head" => %{"ref" => "refs/heads/old-branch", "sha" => "def456"},
          "base" => %{"ref" => "refs/heads/main"},
          "mergeable_state" => "merged",
          "blocked_on" => "",
          "is_wip" => false
        }
      ]
    end

    defp current_pull do
      %{
        "number" => "42",
        "state" => "open",
        "title" => "Repo provider refactor",
        "body" => "Implements CNB support",
        "head" => %{"ref" => "refs/heads/feature/cnb-provider", "sha" => "abc123"},
        "base" => %{"ref" => "refs/heads/main"},
        "mergeable_state" => "mergeable",
        "blocked_on" => "",
        "is_wip" => false
      }
    end

    defp reviews do
      [
        %{
          "id" => "9",
          "state" => "approved",
          "body" => "looks good",
          "created_at" => "2026-04-23T00:00:00Z",
          "updated_at" => "2026-04-23T00:05:00Z",
          "author" => %{"username" => "reviewer"}
        }
      ]
    end

    defp review_comments do
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
      ]
    end

    defp commit_statuses do
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
      }
    end

    defp issue_comments do
      [
        %{
          "id" => "55",
          "body" => "top-level note",
          "created_at" => "2026-04-23T00:25:00Z",
          "updated_at" => "2026-04-23T00:25:00Z",
          "author" => %{"username" => "reviewer"}
        }
      ]
    end

    defp build_logs(opts \\ []) do
      sn = Keyword.get(opts, :sn, "1001")

      %{
        "data" => [
          %{
            "buildLogUrl" => "https://cnb.cool/acme/widgets/-/build/logs/#{sn}",
            "commitTitle" => "Repo provider refactor",
            "createTime" => "2026-04-23T00:20:00Z",
            "duration" => 3210,
            "event" => "pull_request",
            "eventUrl" => "https://cnb.cool/acme/widgets/-/pulls/42",
            "pipelineFailCount" => 0,
            "pipelineSuccessCount" => 1,
            "pipelineTotalCount" => 1,
            "sha" => "abc123",
            "slug" => "acme/widgets",
            "sn" => sn,
            "sourceRef" => "feature/cnb-provider",
            "status" => "success",
            "title" => "CI for Repo provider refactor"
          }
        ],
        "init" => true,
        "timestamp" => 1_777_777_777,
        "total" => 1
      }
    end

    defp build_status do
      %{
        "status" => "success",
        "pipelinesStatus" => %{
          "pipeline-1" => %{
            "duration" => 3210,
            "id" => "pipeline-1",
            "labels" => [%{"key" => "job", "value" => ["ci"]}],
            "name" => "ci",
            "stages" => [
              %{
                "duration" => 100,
                "id" => "stage-1",
                "name" => "checkout",
                "status" => "success"
              },
              %{"duration" => 2500, "id" => "stage-2", "name" => "test", "status" => "success"}
            ],
            "status" => "success"
          }
        }
      }
    end

    defp build_stage(id, name, content) do
      %{
        "content" => content,
        "duration" => 100,
        "endTime" => 1_777_777_877,
        "error" => "",
        "id" => id,
        "name" => name,
        "startTime" => 1_777_777_777,
        "status" => "success"
      }
    end
  end

  test "cnb helper authenticates with CNB token" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "auth-status"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert output == "CNB auth ok as tester\n"

      assert_receive {:cnb_request, request}
      assert request.method == "GET"
      assert request.path == "/user"
      assert request.headers["authorization"] == "Bearer test-token"
    end)
  end

  test "cnb helper retries transient GET failures and succeeds after a 429 response" do
    with_cnb_helper(:user_status_once_429, fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "auth-status"],
          cd: root,
          env:
            helper_env(api_base_url) ++
              [
                {"SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES", "2"},
                {"SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS", "0"}
              ],
          stderr_to_stdout: true
        )

      assert output == "CNB auth ok as tester\n"

      assert_receive {:cnb_request, %{path: "/user"}}
      assert_receive {:cnb_request, %{path: "/user"}}
    end)
  end

  test "cnb helper times out GET requests with a clear error" do
    with_cnb_helper({:sleep_user, 1_200}, fn root, helper, api_base_url ->
      {output, status} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "auth-status"],
          cd: root,
          env:
            helper_env(api_base_url) ++
              [
                {"SYMPHONY_REPO_PROVIDER_HTTP_TIMEOUT_SECONDS", "1"},
                {"SYMPHONY_REPO_PROVIDER_MAX_HTTP_RETRIES", "0"},
                {"SYMPHONY_REPO_PROVIDER_RETRY_BACKOFF_SECONDS", "0"}
              ],
          stderr_to_stdout: true
        )

      assert status == 1
      assert output =~ "CNB API GET"
      assert output =~ ":timeout"
    end)
  end

  test "cnb helper resolves the current branch PR and normalizes pr-view output" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-view", "--json", "url,state,headRefOid", "-q", ".url"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      Snapshot.assert_snapshot!("repo_provider_contract/cnb/pr_view_url.stdout.txt", output)
    end)
  end

  test "cnb helper creates PRs with provider-derived defaults" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          [
            "--provider",
            "cnb",
            "pr-create",
            "--title",
            "Add CNB provider support",
            "--body",
            "Implements the first CNB slice"
          ],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"

      assert_receive {:cnb_request, %{method: "POST", path: create_path, body: body}}
      assert create_path =~ "/-/pulls"

      assert Jason.decode!(body) == %{
               "base" => "main",
               "body" => "Implements the first CNB slice",
               "head" => "feature/cnb-provider",
               "title" => "Add CNB provider support"
             }
    end)
  end

  test "cnb helper renders pr-checks summaries and supports JSON queries" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {summary_output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-checks"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert summary_output == "ci: completed/success (green)\n"

      {json_output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-checks", "--json", "-q", ".[0].name"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert json_output == "ci\n"
    end)
  end

  test "cnb helper translates GitHub-style api endpoints to CNB review and check surfaces" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {comment_output, 0} =
        CommandEnv.system_cmd(
          helper,
          [
            "--provider",
            "cnb",
            "api",
            "repos/{owner}/{repo}/pulls/42/comments",
            "--jq",
            ".[0].pull_request_review_id"
          ],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert comment_output == "9\n"

      {checks_output, 0} =
        CommandEnv.system_cmd(
          helper,
          [
            "--provider",
            "cnb",
            "api",
            "--method",
            "GET",
            "repos/{owner}/{repo}/commits/abc123/check-runs",
            "--jq",
            ".total_count"
          ],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert checks_output == "1\n"
    end)
  end

  test "cnb helper preserves the CLI contract for JSON output, scalar output, and invalid queries" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {json_output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-view", "--json", "url,state"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      Snapshot.assert_snapshot!("repo_provider_contract/cnb/pr_view.stdout.json", json_output)

      {scalar_output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-view", "--json", "url", "-q", ".url"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      Snapshot.assert_snapshot!(
        "repo_provider_contract/cnb/pr_view_scalar.stdout.txt",
        scalar_output
      )

      {invalid_output, status} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-view", "--json", "url", "-q", ".url // \"\""],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert status == 1

      Snapshot.assert_snapshot!(
        "repo_provider_contract/cnb/invalid_jq.output.txt",
        invalid_output
      )
    end)
  end

  test "cnb helper supports streamed array jq expressions without an external jq binary" do
    with_cnb_helper(fn root, helper, api_base_url ->
      bash = System.find_executable("bash")

      {output, 0} =
        CommandEnv.system_cmd(
          bash,
          [
            helper,
            "--provider",
            "cnb",
            "api",
            "repos/{owner}/{repo}/issues/42/comments",
            "--jq",
            ".[].id"
          ],
          cd: root,
          env:
            helper_env(api_base_url) ++
              [
                {"PATH",
                 Enum.join(
                   [runtime_path(root, ~w(git python3)), System.get_env("PATH") || ""],
                   ":"
                 )}
              ],
          stderr_to_stdout: true
        )

      assert output == "55\n"
    end)
  end

  test "cnb helper lists CNB build runs for the current branch" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          [
            "--provider",
            "cnb",
            "run-list",
            "--branch",
            "feature/cnb-provider",
            "--json",
            "id,headSha,url",
            "-q",
            ".[0].id"
          ],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      Snapshot.assert_snapshot!("repo_provider_contract/cnb/run_list_first_id.stdout.txt", output)

      assert_receive {:cnb_request, %{path: "/acme%2Fwidgets/-/build/logs", query: query}}
      assert query["sourceRef"] == "feature/cnb-provider"
      assert query["sha"] == "abc123"
    end)
  end

  test "cnb helper streams stage logs for run-view --log" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, 0} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "run-view", "1001", "--log"],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      Snapshot.assert_snapshot!("repo_provider_contract/cnb/run_view_log.stdout.txt", output)
    end)
  end

  test "cnb helper surfaces actionable errors when CNB build scope is missing on the symphony run-list path" do
    with_cnb_helper(:build_scope_forbidden, fn root, helper, api_base_url ->
      {output, status} =
        CommandEnv.system_cmd(
          helper,
          [
            "--provider",
            "cnb",
            "run-list",
            "--branch",
            "feature/cnb-provider",
            "--json",
            "id",
            "-q",
            ".[0].id"
          ],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert status == 1
      assert output =~ "Grant CNB build authorization"
      assert output =~ "current CNB_TOKEN cannot access run data"
    end)
  end

  test "cnb helper evaluates supported jq queries without an external jq binary" do
    with_cnb_helper(fn root, helper, api_base_url ->
      bash = System.find_executable("bash")

      {output, 0} =
        CommandEnv.system_cmd(
          bash,
          [helper, "--provider", "cnb", "pr-view", "--json", "url", "-q", ".url"],
          cd: root,
          env:
            helper_env(api_base_url) ++
              [
                {"PATH",
                 Enum.join(
                   [runtime_path(root, ~w(git python3)), System.get_env("PATH") || ""],
                   ":"
                 )}
              ],
          stderr_to_stdout: true
        )

      assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"
    end)
  end

  test "cnb helper rejects unsupported jq expressions explicitly" do
    with_cnb_helper(fn root, helper, api_base_url ->
      {output, status} =
        CommandEnv.system_cmd(
          helper,
          ["--provider", "cnb", "pr-view", "--json", "url", "-q", ".url // \"\""],
          cd: root,
          env: helper_env(api_base_url),
          stderr_to_stdout: true
        )

      assert status == 1
      assert output =~ "Unsupported CNB jq expression"
    end)
  end

  test "cnb helper routes pr-view through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-elixir-backend-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'https://cnb.cool/acme/widgets/-/pulls/42\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-view", "--json", "url", "-q", ".url"],
            cd: root,
            env:
              helper_env("http://127.0.0.1:1") ++
                [
                  {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
                ],
            stderr_to_stdout: true
          )

        assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"
        assert File.read!(log_path) =~ "repo-provider --provider cnb pr-view --json url -q .url"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes auth-status, pr-view, and pr-checks through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-auto-read-only-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        case "$*" in
          *"auth-status"*) printf 'CNB auth ok as tester\\n' ;;
          *"pr-view"*) printf 'https://cnb.cool/acme/widgets/-/pulls/42\\n' ;;
          *"pr-checks"*) printf 'ci: completed/success (green)\\n' ;;
          *"pr-land-watch"*) printf 'Checks passed\\n' ;;
          *) printf 'unexpected command\\n' >&2; exit 88 ;;
        esac
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        for {args, expected} <- [
              {["--provider", "cnb", "auth-status"], "CNB auth ok as tester\n"},
              {["--provider", "cnb", "pr-view", "--json", "url", "-q", ".url"], "https://cnb.cool/acme/widgets/-/pulls/42\n"},
              {["--provider", "cnb", "pr-checks", "--watch"], "ci: completed/success (green)\n"},
              {["--provider", "cnb", "pr-land-watch"], "Checks passed\n"}
            ] do
          {output, 0} = CommandEnv.system_cmd(helper, args, cd: root, env: env, stderr_to_stdout: true)
          assert output == expected
        end

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb auth-status"
        assert log =~ "repo-provider --provider cnb pr-view --json url -q .url"
        assert log =~ "repo-provider --provider cnb pr-checks --watch"
        assert log =~ "repo-provider --provider cnb pr-land-watch"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes api through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-auto-api-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf '55\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            [
              "--provider",
              "cnb",
              "api",
              "repos/{owner}/{repo}/issues/42/comments",
              "--jq",
              ".[0].id"
            ],
            cd: root,
            env:
              helper_env("http://127.0.0.1:1") ++
                [
                  {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
                ],
            stderr_to_stdout: true
          )

        assert output == "55\n"

        assert File.read!(log_path) =~
                 "repo-provider --provider cnb api repos/{owner}/{repo}/issues/42/comments --jq .[0].id"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes run-list and run-view through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-elixir-runs-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        case "$*" in
          *"run-list"*) printf '1001\\n' ;;
          *"run-view"*) printf 'Run 1001: success\\n' ;;
          *) printf 'unexpected command\\n' >&2; exit 88 ;;
        esac
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        {run_list_output, 0} =
          CommandEnv.system_cmd(
            helper,
            [
              "--provider",
              "cnb",
              "run-list",
              "--branch",
              "feature/cnb-provider",
              "--json",
              "id",
              "-q",
              ".[0].id"
            ],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        {run_view_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "run-view", "1001", "--log"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        assert run_list_output == "1001\n"
        assert run_view_output == "Run 1001: success\n"

        log = File.read!(log_path)

        assert log =~
                 "repo-provider --provider cnb run-list --branch feature/cnb-provider --json id -q .[0].id"

        assert log =~ "repo-provider --provider cnb run-view 1001 --log"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes run-list and run-view through symphony even when python is unusable" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-auto-runs-#{unique}")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")
      runtime_bin = runtime_path(root, ~w(git))

      write_executable!(
        Path.join(runtime_bin, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        case "$*" in
          *"run-list"*) printf '1001\\n' ;;
          *"run-view"*) printf 'Run 1001: success\\n' ;;
          *) printf 'unexpected command\\n' >&2; exit 88 ;;
        esac
        """
      )

      write_executable!(
        Path.join(runtime_bin, "python3"),
        """
        #!/bin/sh
        printf 'unexpected python3 invocation\\n' >&2
        exit 99
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env(start_test_server!(:success)) ++
            [
              {"PATH", Enum.join([runtime_bin, System.get_env("PATH") || ""], ":")}
            ]

        {run_list_output, 0} =
          CommandEnv.system_cmd(
            helper,
            [
              "--provider",
              "cnb",
              "run-list",
              "--branch",
              "feature/cnb-provider",
              "--json",
              "id",
              "-q",
              ".[0].id"
            ],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        {run_view_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "run-view", "1001", "--log"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        assert run_list_output == "1001\n"
        assert run_view_output == "Run 1001: success\n"

        log = File.read!(log_path)

        assert log =~
                 "repo-provider --provider cnb run-list --branch feature/cnb-provider --json id -q .[0].id"

        assert log =~ "repo-provider --provider cnb run-view 1001 --log"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes PR mutations through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-elixir-mutations-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'https://cnb.cool/acme/widgets/-/pulls/42\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        for args <- [
              ["--provider", "cnb", "pr-create", "--title", "Add CNB provider support"],
              ["--provider", "cnb", "pr-edit", "42", "--body", "updated"],
              ["--provider", "cnb", "pr-merge", "42", "--squash"],
              ["--provider", "cnb", "pr-close", "42"]
            ] do
          {output, 0} = CommandEnv.system_cmd(helper, args, cd: root, env: env, stderr_to_stdout: true)
          assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"
        end

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb pr-create --title Add CNB provider support"
        assert log =~ "repo-provider --provider cnb pr-edit 42 --body updated"
        assert log =~ "repo-provider --provider cnb pr-merge 42 --squash"
        assert log =~ "repo-provider --provider cnb pr-close 42"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes review comment commands through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-review-comments-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        case "$*" in
          *"pr-review-comments"*) printf '[{"id":101,"body":"inline note"}]\\n' ;;
          *"pr-reply-review-comment"*) printf '{"id":102,"body":"[codex] acknowledged","in_reply_to_id":101}\\n' ;;
          *) printf 'unexpected command\\n' >&2; exit 87 ;;
        esac
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        {list_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-review-comments", "42"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        {reply_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-reply-review-comment", "101", "42", "--body", "[codex] acknowledged"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        assert Jason.decode!(list_output) |> List.first() |> Map.fetch!("id") == 101
        assert Jason.decode!(reply_output)["in_reply_to_id"] == 101

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb pr-review-comments 42"
        assert log =~ "repo-provider --provider cnb pr-reply-review-comment 101 42 --body [codex] acknowledged"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes pr-reviews through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-reviews-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf '[{"id":9,"state":"APPROVED"}]\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-reviews", "42"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        assert Jason.decode!(output) |> List.first() |> Map.fetch!("state") == "APPROVED"

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb pr-reviews 42"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes issue comment commands through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-issue-comments-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        case "$*" in
          *"pr-issue-comments"*) printf '[{"id":55,"body":"top-level note"}]\\n' ;;
          *"pr-add-issue-comment"*) printf '{"id":56,"body":"[codex] acknowledged"}\\n' ;;
          *) printf 'unexpected command\\n' >&2; exit 87 ;;
        esac
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        {list_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-issue-comments", "42"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        {create_output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-add-issue-comment", "42", "--body", "[codex] acknowledged"],
            cd: root,
            env: env,
            stderr_to_stdout: true
          )

        assert Jason.decode!(list_output) |> List.first() |> Map.fetch!("id") == 55
        assert Jason.decode!(create_output)["id"] == 56

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb pr-issue-comments 42"
        assert log =~ "repo-provider --provider cnb pr-add-issue-comment 42 --body [codex] acknowledged"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes validated PR writes through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-auto-mutations-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'https://cnb.cool/acme/widgets/-/pulls/42\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        env =
          helper_env("http://127.0.0.1:1") ++
            [
              {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
            ]

        for args <- [
              ["--provider", "cnb", "pr-create", "--title", "Add CNB provider support"],
              ["--provider", "cnb", "pr-edit", "42", "--body", "updated"],
              ["--provider", "cnb", "pr-merge", "42", "--squash"],
              ["--provider", "cnb", "pr-close", "42"]
            ] do
          {output, 0} = CommandEnv.system_cmd(helper, args, cd: root, env: env, stderr_to_stdout: true)
          assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"
        end

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider cnb pr-create --title Add CNB provider support"
        assert log =~ "repo-provider --provider cnb pr-edit 42 --body updated"
        assert log =~ "repo-provider --provider cnb pr-merge 42 --squash"
        assert log =~ "repo-provider --provider cnb pr-close 42"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes pr-merge through symphony even when python is unusable" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-auto-merge-#{unique}")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")
      runtime_bin = runtime_path(root, ~w(git))

      write_executable!(
        Path.join(runtime_bin, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'https://cnb.cool/acme/widgets/-/pulls/42\\n'
        """
      )

      write_executable!(
        Path.join(runtime_bin, "python3"),
        """
        #!/bin/sh
        printf 'unexpected python3 invocation\\n' >&2
        exit 99
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-merge", "42", "--squash"],
            cd: root,
            env:
              helper_env(start_test_server!(:success)) ++
                [
                  {"PATH", Enum.join([runtime_bin, System.get_env("PATH") || ""], ":")}
                ],
            stderr_to_stdout: true
          )

        assert output == "https://cnb.cool/acme/widgets/-/pulls/42\n"
        assert File.read!(log_path) =~ "repo-provider --provider cnb pr-merge 42 --squash"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes pr-checks through symphony" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-elixir-checks-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'ci: completed/success (green)\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            ["--provider", "cnb", "pr-checks", "--watch"],
            cd: root,
            env:
              helper_env("http://127.0.0.1:1") ++
                [
                  {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
                ],
            stderr_to_stdout: true
          )

        assert output == "ci: completed/success (green)\n"
        assert File.read!(log_path) =~ "repo-provider --provider cnb pr-checks --watch"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb helper routes api through symphony with explicit PATH override" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cnb-elixir-api-#{unique}")
    bin_dir = Path.join(root, "runtime-bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      init_git_repo!(root)
      helper = copy_helper!(root)
      File.write!(log_path, "")

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf '55\\n'
        """
      )

      with_env(%{"SYMPHONY_LOG" => log_path}, fn ->
        {output, 0} =
          CommandEnv.system_cmd(
            helper,
            [
              "--provider",
              "cnb",
              "api",
              "repos/{owner}/{repo}/issues/42/comments",
              "--jq",
              ".[0].id"
            ],
            cd: root,
            env:
              helper_env("http://127.0.0.1:1") ++
                [
                  {"PATH", Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}
                ],
            stderr_to_stdout: true
          )

        assert output == "55\n"

        assert File.read!(log_path) =~
                 "repo-provider --provider cnb api repos/{owner}/{repo}/issues/42/comments --jq .[0].id"
      end)
    after
      File.rm_rf!(root)
    end
  end

  defp with_cnb_helper(fun), do: with_cnb_helper(:success, fun)

  defp with_cnb_helper(mode, fun) do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "cnb-repo-provider-helper-test-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      runtime_bin = runtime_path(root, ~w(git python3))
      helper = copy_helper!(root)
      api_base_url = start_test_server!(normalize_helper_mode(mode))

      with_env(%{"PATH" => Enum.join([runtime_bin, System.get_env("PATH") || ""], ":")}, fn ->
        fun.(root, helper, api_base_url)
      end)
    after
      File.rm_rf!(root)
    end
  end

  defp start_test_server!(mode) do
    mode = normalize_server_mode(mode)

    pid =
      start_supervised!({Bandit, plug: {TestPlug, owner: self(), mode: mode}, scheme: :http, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp normalize_server_mode({:user_status_once, status}) when is_integer(status) do
    counter = start_supervised!({Agent, fn -> 0 end})
    {:user_status_once, counter, status}
  end

  defp normalize_server_mode(mode), do: mode

  defp copy_helper!(root) do
    {:ok, bundled_dir} = AutomationPack.bundled_source_dir()
    bin_dir = Path.join(root, "bin")
    File.mkdir_p!(bin_dir)

    source = Path.join([bundled_dir, "bin", "repo-provider"])
    destination = Path.join(bin_dir, "repo-provider")
    File.cp!(source, destination)
    File.chmod!(destination, 0o755)

    Path.join(bin_dir, "repo-provider")
  end

  defp helper_env(api_base_url) do
    [
      {"CNB_TOKEN", "test-token"},
      {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"},
      {"SYMPHONY_REPO_PROVIDER_API_BASE_URL", api_base_url},
      {"SYMPHONY_REPO_PROVIDER_WEB_BASE_URL", "https://cnb.cool"}
    ]
  end

  defp normalize_helper_mode(:user_status_once_429), do: {:user_status_once, 429}
  defp normalize_helper_mode(:sleep_user), do: {:sleep_user, 150}
  defp normalize_helper_mode(mode), do: mode

  defp runtime_path(root, commands) do
    bin_dir = Path.join(root, "runtime-bin")
    File.rm_rf!(bin_dir)
    File.mkdir_p!(bin_dir)

    install_real_symphony!(bin_dir)

    Enum.each(commands, fn command ->
      executable = System.find_executable(command)
      File.ln_s!(executable, Path.join(bin_dir, command))
    end)

    bin_dir
  end

  defp install_real_symphony!(bin_dir) do
    elixir = System.find_executable("elixir")
    elixir_root = Path.expand("../../..", __DIR__)

    beam_paths =
      elixir_root
      |> Path.join("_build/test/lib/*/ebin")
      |> Path.wildcard()
      |> Enum.sort()

    load_path_args = Enum.map_join(beam_paths, " ", &"-pa '#{&1}'")

    write_executable!(
      Path.join(bin_dir, "symphony"),
      """
      #!/bin/sh
      export MIX_ENV="${MIX_ENV:-test}"
      exec '#{elixir}' #{load_path_args} -e 'Application.load(:symphony_elixir); SymphonyElixir.CLI.main(System.argv())' -- "$@"
      """
    )
  end

  defp write_executable!(path, contents) do
    File.write!(path, contents)
    File.chmod!(path, 0o755)
  end

  defp with_env(overrides, fun) do
    keys = Map.keys(overrides)
    previous = Map.new(keys, fn key -> {key, System.get_env(key)} end)

    try do
      Enum.each(overrides, fn {key, value} -> System.put_env(key, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp init_git_repo!(root) do
    {_, 0} = CommandEnv.system_cmd("git", ["init", "--initial-branch=main"], cd: root)
    File.write!(Path.join(root, "README.md"), "helper test\n")
    {_, 0} = CommandEnv.system_cmd("git", ["add", "README.md"], cd: root)

    {_, 0} =
      CommandEnv.system_cmd(
        "git",
        [
          "-c",
          "user.name=Test User",
          "-c",
          "user.email=test@example.com",
          "commit",
          "-m",
          "init"
        ],
        cd: root
      )

    {_, 0} = CommandEnv.system_cmd("git", ["checkout", "-b", "feature/cnb-provider"], cd: root)

    {_, 0} =
      CommandEnv.system_cmd("git", ["remote", "add", "origin", "https://cnb.cool/acme/widgets.git"], cd: root)
  end
end
