defmodule SymphonyElixir.RepoProviderCLITest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.CLI.RepoProvider, as: RepoProviderCLI
  alias SymphonyElixir.Platform.CommandEnv

  defmodule TestPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      conn = fetch_query_params(conn)
      {:ok, body, conn} = read_body(conn)

      send(opts[:owner], {:cli_cnb_request, %{method: conn.method, path: conn.request_path, query: conn.query_params, body: body}})

      case response_for(opts[:mode] || :success, conn.method, conn.request_path, conn.query_params) do
        {status, payload} -> json(conn, status, payload)
      end
    end

    defp response_for(:success, "GET", "/user", _query), do: {200, %{"username" => "tester"}}
    defp response_for({:checks_sequence, _counter}, "GET", "/user", _query), do: {200, %{"username" => "tester"}}

    defp response_for(mode, "GET", "/acme%2Fwidgets/-/pulls", %{"order_by" => "-updated_at", "page" => "1", "page_size" => "100", "state" => state})
         when mode in [:success, :build_scope_forbidden] and state in ["open", "all"] do
      {200, [current_pull()]}
    end

    defp response_for({:checks_sequence, _counter}, "GET", "/acme%2Fwidgets/-/pulls", %{
           "order_by" => "-updated_at",
           "page" => "1",
           "page_size" => "100",
           "state" => state
         })
         when state in ["open", "all"] do
      {200, [current_pull()]}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42", _query), do: {200, current_pull()}
    defp response_for({:checks_sequence, _counter}, "GET", "/acme%2Fwidgets/-/pulls/42", _query), do: {200, current_pull()}
    defp response_for(:success, "POST", "/acme%2Fwidgets/-/pulls", _query), do: {201, %{"number" => "42"}}
    defp response_for(:success, "PATCH", "/acme%2Fwidgets/-/pulls/42", _query), do: {200, %{"number" => "42"}}
    defp response_for(:success, "PUT", "/acme%2Fwidgets/-/pulls/42/merge", _query), do: {200, %{"number" => "42"}}

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42/reviews", %{"page" => "1", "page_size" => "100"}) do
      {200, [%{"id" => "9", "state" => "approved", "author" => %{"username" => "reviewer"}}]}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42/comments", %{"page" => "1", "page_size" => "100"}) do
      {200,
       [
         %{
           "id" => "55",
           "body" => "top-level note",
           "created_at" => "2026-04-23T00:25:00Z",
           "updated_at" => "2026-04-23T00:26:00Z",
           "author" => %{"username" => "reviewer"}
         }
       ]}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42/comments", %{"page" => "2", "page_size" => "100"}) do
      {200, []}
    end

    defp response_for(:success, "POST", "/acme%2Fwidgets/-/pulls/42/comments", _query) do
      {201,
       %{
         "id" => "56",
         "body" => "[codex] acknowledged",
         "author" => %{"username" => "codex"}
       }}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42/reviews/9/comments", %{"page" => "1", "page_size" => "100"}) do
      {200,
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
    end

    defp response_for(:success, "POST", "/acme%2Fwidgets/-/pulls/42/reviews/9/replies", _query) do
      {201,
       %{
         "id" => "102",
         "review_id" => "9",
         "reply_to_comment_id" => "101",
         "body" => "[codex] acknowledged",
         "author" => %{"username" => "codex"}
       }}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/pulls/42/commit-statuses", _query), do: {200, commit_statuses()}

    defp response_for({:checks_sequence, counter}, "GET", "/acme%2Fwidgets/-/pulls/42/commit-statuses", _query) do
      current =
        Agent.get_and_update(counter, fn attempts ->
          {attempts, attempts + 1}
        end)

      if current == 0 do
        {200, pending_commit_statuses()}
      else
        {200, commit_statuses()}
      end
    end

    defp response_for(:success, "GET", "/example-org%2FAI%2Fsample-cnb-project/-/pulls/42/comments", %{"page" => "1", "page_size" => "2"}) do
      {200, [%{"id" => "77", "body" => "nested repo path works", "author" => %{"username" => "reviewer"}}]}
    end

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/build/logs", %{"sourceRef" => "feature/cnb-provider", "sha" => "abc123"}),
      do: {200, build_logs()}

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/build/logs", %{"sn" => "1001"}), do: {200, build_logs()}

    defp response_for(:build_scope_forbidden, "GET", "/acme%2Fwidgets/-/build/logs", _query),
      do: {403, %{"errcode" => 7, "errmsg" => "The bill authorization scope cannot access the current request."}}

    defp response_for(:build_scope_forbidden, "GET", "/acme%2Fwidgets/-/build/status/1001", _query),
      do: {403, %{"errcode" => 7, "errmsg" => "The bill authorization scope cannot access the current request."}}

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/build/status/1001", _query), do: {200, build_status()}

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/build/logs/stage/1001/pipeline-1/stage-1", _query),
      do: {200, build_stage("stage-1", "checkout", ["cloning repo", "checkout complete"])}

    defp response_for(:success, "GET", "/acme%2Fwidgets/-/build/logs/stage/1001/pipeline-1/stage-2", _query),
      do: {200, build_stage("stage-2", "test", ["mix test", "80 tests, 0 failures"])}

    defp response_for(_mode, _method, _path, _query), do: {404, %{"error" => "not_found"}}

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

    defp build_logs do
      %{
        "data" => [
          %{
            "buildLogUrl" => "https://cnb.cool/acme/widgets/-/build/logs/1001",
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
            "sn" => "1001",
            "sourceRef" => "feature/cnb-provider",
            "status" => "success",
            "title" => "CI for Repo provider refactor"
          }
        ],
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
            "name" => "ci",
            "stages" => [
              %{"duration" => 100, "id" => "stage-1", "name" => "checkout", "status" => "success"},
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
        "id" => id,
        "name" => name,
        "status" => "success"
      }
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

    defp pending_commit_statuses do
      %{
        "state" => "pending",
        "statuses" => [
          %{
            "context" => "ci",
            "state" => "pending",
            "description" => "still running",
            "created_at" => "2026-04-23T00:20:00Z",
            "updated_at" => "2026-04-23T00:20:00Z",
            "target_url" => "https://ci.example.test/runs/1"
          }
        ]
      }
    end

    defp json(conn, status, payload) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end
  end

  test "current-kind does not require workflow or acknowledgement" do
    deps = cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "cnb"})

    assert {"cnb\n", "", 0} = RepoProviderCLI.evaluate(["current-kind"], deps)
    assert {"gitlab\n", "", 0} = RepoProviderCLI.evaluate(["--provider", "gitlab", "current-kind"], deps)
  end

  test "main starts runtime dependencies before evaluating repo-provider commands" do
    parent = self()

    deps =
      cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "github"})
      |> Map.merge(%{
        ensure_runtime_started: fn ->
          send(parent, :runtime_started)
          :ok
        end,
        stdout: fn output -> send(parent, {:stdout, output}) end,
        stderr: fn output -> send(parent, {:stderr, output}) end,
        halt: fn status -> throw({:halt, status}) end
      })

    assert catch_throw(RepoProviderCLI.main(["current-kind"], deps)) == {:halt, 0}
    assert_received :runtime_started
    assert_received {:stdout, "github\n"}
    refute_received {:stderr, _output}
  end

  test "main fails clearly when runtime dependencies cannot start" do
    parent = self()

    deps =
      cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "github"})
      |> Map.merge(%{
        ensure_runtime_started: fn -> {:error, :boom} end,
        stdout: fn output -> send(parent, {:stdout, output}) end,
        stderr: fn output -> send(parent, {:stderr, output}) end,
        halt: fn status -> throw({:halt, status}) end
      })

    assert catch_throw(RepoProviderCLI.main(["current-kind"], deps)) == {:halt, 1}
    assert_received {:stderr, "Failed to start repo-provider runtime dependencies: :boom\n"}
    refute_received {:stdout, _output}
  end

  test "main suppresses runtime logs so json smoke output stays machine-readable" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-json-contract-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          printf 'Logged in to github.com as json-contract-user\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{})
        |> Map.merge(%{
          ensure_runtime_started: fn ->
            Logger.bare_log(:info, "repo provider runtime log that must stay off stdout")
            :ok
          end,
          halt: fn status -> throw({:halt, status}) end
        })

      parent = self()

      wrapped_deps =
        deps
        |> Map.put(:stdout, fn output -> send(parent, {:stdout, output}) end)
        |> Map.put(:stderr, fn output -> send(parent, {:stderr, output}) end)

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert catch_throw(RepoProviderCLI.main(["smoke", "--provider", "github", "--json"], wrapped_deps)) ==
                 {:halt, 0}
      end)

      assert_received {:stdout, stdout}
      refute stdout =~ "repo provider runtime log"
      assert {:ok, payload} = Jason.decode(stdout)
      assert payload["provider_kind"] == "github"
      assert payload["ok"] == true
      assert payload["smoke_mode"] == "read_only"
      refute_received {:stderr, _output}
    after
      File.rm_rf!(root)
    end
  end

  test "repo-provider smoke runs through the symphony CLI path and returns JSON output" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-smoke-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          printf 'Logged in to github.com as smoke-user\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$3" = "42" ]; then
          printf '{"url":"https://github.com/acme/widgets/pull/42","state":"OPEN","title":"Repo provider refactor","body":"Implements Elixir backend","headRefName":"feature/backend","headRefOid":"abc123","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}\\n'
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/pulls/42/reviews" ]; then
          printf '[{"id":9,"body":"looks good","submitted_at":"2026-04-23T00:05:00Z","state":"approved","user":{"login":"reviewer","type":"User"}}]\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "checks" ] && [ "$3" = "42" ]; then
          printf '[{"bucket":"pass","completedAt":"2026-04-23T00:21:00Z","description":"green","link":"https://ci.example.test/runs/1","name":"ci","startedAt":"2026-04-23T00:20:00Z","state":"SUCCESS"}]\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps = cli_deps(%{})

      output =
        with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
          {stdout, "", 0} =
            RepoProviderCLI.evaluate(["smoke", "--provider", "github", "--repo", "acme/widgets", "--pr", "42", "--json"], deps)

          stdout
        end)

      payload = Jason.decode!(output)

      assert payload["ok"] == true
      assert payload["provider_kind"] == "github"
      assert payload["repo_provider_runtime"] == "symphony"
      assert payload["repository"] == "acme/widgets"
      assert payload["smoke_mode"] == "read_only"
      assert payload["probe_count"] == 5
      assert payload["passed_count"] == 5

      assert Enum.map(payload["probes"], & &1["id"]) == [
               "current-kind",
               "auth-status",
               "pr-view",
               "pr-reviews",
               "pr-checks"
             ]

      assert Enum.find(payload["probes"], &(&1["id"] == "pr-reviews"))["summary"] ==
               "APPROVED"
    after
      File.rm_rf!(root)
    end
  end

  test "repo-provider smoke surfaces invalid options with usage" do
    deps = cli_deps(%{})

    assert {"", stderr, 64} = RepoProviderCLI.evaluate(["smoke", "--wat"], deps)
    assert stderr =~ "Invalid option(s)"
    assert stderr =~ "symphony repo-provider smoke"
  end

  test "repo-provider destructive smoke validates required and conflicting options" do
    deps = cli_deps(%{})

    assert {"", stderr, 64} = RepoProviderCLI.evaluate(["smoke", "--destructive"], deps)
    assert stderr =~ "Destructive smoke requires --head unless --auto-provision-cnb-pipeline is enabled"

    assert {"", stderr, 64} =
             RepoProviderCLI.evaluate(["smoke", "--destructive", "--head", "feature/smoke", "--pr", "42"], deps)

    assert stderr =~ "Destructive smoke does not accept --pr"
  end

  test "repo-provider CNB auto-provision smoke validates provider and head constraints" do
    github_deps = cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "github"})

    assert {"", stderr, 64} =
             RepoProviderCLI.evaluate(["smoke", "--destructive", "--auto-provision-cnb-pipeline"], github_deps)

    assert stderr =~ "--auto-provision-cnb-pipeline is only supported for --provider cnb"

    cnb_deps = cli_deps(%{"SYMPHONY_REPO_PROVIDER_KIND" => "cnb"})

    assert {"", stderr, 64} =
             RepoProviderCLI.evaluate(
               ["smoke", "--destructive", "--auto-provision-cnb-pipeline", "--head", "feature/smoke"],
               cnb_deps
             )

    assert stderr =~ "--auto-provision-cnb-pipeline does not accept --head"
  end

  test "github pr-view returns scalar output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")
    git_path = Path.join(bin_dir, "git")
    gh_log_path = Path.join(root, "gh.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      File.write!(gh_log_path, "")

      write_executable!(
        git_path,
        """
        #!/bin/sh
        if [ "$1" = "branch" ] && [ "$2" = "--show-current" ]; then
          printf 'feature/current-branch\\n'
          exit 0
        fi
        printf 'unexpected git invocation: %s\\n' "$*" >&2
        exit 98
        """
      )

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$GH_LOG"
        if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$3" = "feature/current-branch" ]; then
          printf '{"url":"https://example.test/pr/123","state":"OPEN","title":"Repo provider refactor","body":"Implements Elixir backend","headRefName":"feature/backend","headRefOid":"abc123","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN"}\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(
        %{
          "PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":"),
          "GH_LOG" => gh_log_path
        },
        fn ->
          assert {"https://example.test/pr/123\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-view", "--json", "url", "-q", ".url"], deps)

          log = File.read!(gh_log_path)
          assert log =~ "pr view feature/current-branch --repo acme/widgets"
        end
      )
    after
      File.rm_rf!(root)
    end
  end

  test "github pr-checks and PR writes return normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-wridemo-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")
    git_path = Path.join(bin_dir, "git")
    gh_log_path = Path.join(root, "gh.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      File.write!(gh_log_path, "")

      write_executable!(
        git_path,
        """
        #!/bin/sh
        if [ "$1" = "branch" ] && [ "$2" = "--show-current" ]; then
          printf 'feature/current-branch\\n'
          exit 0
        fi
        printf 'unexpected git invocation: %s\\n' "$*" >&2
        exit 98
        """
      )

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$GH_LOG"
        if [ "$1" = "pr" ] && [ "$2" = "checks" ] && [ "$3" = "feature/current-branch" ]; then
          printf '[{"bucket":"pass","completedAt":"2026-04-23T00:21:00Z","description":"green","link":"https://ci.example.test/runs/1","name":"ci","startedAt":"2026-04-23T00:20:00Z","state":"SUCCESS"}]\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "view" ] && [ "$3" = "feature/current-branch" ]; then
          printf 'https://github.com/acme/widgets/pull/42\\n'
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "edit" ] && [ "$3" = "feature/current-branch" ]; then
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "close" ] && [ "$3" = "feature/current-branch" ]; then
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(
        %{
          "PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":"),
          "GH_LOG" => gh_log_path
        },
        fn ->
          assert {"ci: completed/success (green)\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-checks"], deps)

          assert {"https://github.com/acme/widgets/pull/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-edit", "--title", "Updated title"], deps)

          assert {"https://github.com/acme/widgets/pull/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-add-label", "release-ready"], deps)

          assert {"https://github.com/acme/widgets/pull/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-close", "--comment", "[codex] restarting from a fresh branch"], deps)

          log = File.read!(gh_log_path)
          assert log =~ "pr checks feature/current-branch --repo acme/widgets"
          assert log =~ "pr view feature/current-branch --repo acme/widgets --json url --jq .url"
          assert log =~ "pr edit feature/current-branch --repo acme/widgets --title Updated title"
          assert log =~ "pr edit feature/current-branch --repo acme/widgets --add-label release-ready"
          assert log =~ "pr close feature/current-branch --repo acme/widgets --comment [codex] restarting from a fresh branch"
        end
      )
    after
      File.rm_rf!(root)
    end
  end

  test "repo-provider CLI carries repo path and remote env into provider git lookups" do
    unique = System.unique_integer([:positive, :monotonic])
    repo_path = Path.join(System.tmp_dir!(), "repo-provider-cli-context-#{unique}")

    try do
      File.rm_rf!(repo_path)
      File.mkdir_p!(repo_path)

      deps =
        %{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PATH" => repo_path,
          "SYMPHONY_REPO_REMOTE" => "upstream"
        }
        |> cli_deps()
        |> Map.put(:command_opts, fn ->
          [
            command_runner: fn
              "git", ["-C", ^repo_path, "remote", "get-url", "upstream"] ->
                {:ok, "git@github.com:env-remote/widgets.git\n"}

              "git", ["-C", ^repo_path, "branch", "--show-current"] ->
                {:ok, "feature/context-path\n"}

              "gh", ["pr", "view", "feature/context-path", "--repo", "env-remote/widgets", "--json", _fields] ->
                {:ok, Jason.encode!(%{"url" => "https://github.com/env-remote/widgets/pull/42"})}

              command, args ->
                flunk("unexpected command: #{inspect({command, args})}")
            end
          ]
        end)

      assert {"https://github.com/env-remote/widgets/pull/42\n", "", 0} =
               RepoProviderCLI.evaluate(["pr-view", "--json", "url", "-q", ".url"], deps)
    after
      File.rm_rf!(repo_path)
    end
  end

  test "github api returns normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-api-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets" ] && [ "$3" = "--method" ] && [ "$4" = "GET" ]; then
          printf '{"full_name":"acme/widgets","private":false}\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert {"acme/widgets\n", "", 0} =
                 RepoProviderCLI.evaluate(["api", "repos/{owner}/{repo}", "-q", ".full_name"], deps)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "github review comment commands return normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-review-comments-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/pulls/42/comments" ] && [ "$3" = "--method" ] && [ "$4" = "GET" ]; then
          printf '[{"id":101,"body":"inline note","path":"lib/example.ex","commit_id":"abc123","pull_request_review_id":9,"in_reply_to_id":null,"user":{"login":"reviewer","type":"User"}}]\\n'
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/pulls/42/comments" ] && [ "$3" = "--method" ] && [ "$4" = "POST" ]; then
          printf '{"id":102,"body":"[codex] acknowledged","path":"lib/example.ex","commit_id":"abc123","pull_request_review_id":9,"in_reply_to_id":101,"user":{"login":"codex","type":"Bot"}}\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert {"101\n", "", 0} =
                 RepoProviderCLI.evaluate(["pr-review-comments", "42", "--json", "id,body", "-q", ".[0].id"], deps)

        {output, "", 0} =
          RepoProviderCLI.evaluate(
            ["pr-reply-review-comment", "101", "42", "--body", "[codex] acknowledged"],
            deps
          )

        assert Jason.decode!(output)["id"] == 102
        assert Jason.decode!(output)["in_reply_to_id"] == 101
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "github pr-reviews returns normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-reviews-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/pulls/42/reviews" ] && [ "$3" = "--method" ] && [ "$4" = "GET" ]; then
          printf '[{"id":9,"body":"looks good","submitted_at":"2026-04-23T00:05:00Z","state":"approved","user":{"login":"reviewer","type":"User"}}]\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert {"APPROVED\n", "", 0} =
                 RepoProviderCLI.evaluate(["pr-reviews", "42", "--json", "state", "-q", ".[0].state"], deps)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "github issue comment commands return normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-issue-comments-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/issues/42/comments" ] && [ "$3" = "--method" ] && [ "$4" = "GET" ]; then
          printf '[{"id":55,"body":"top-level note","user":{"login":"reviewer","type":"User"}}]\\n'
          exit 0
        fi
        if [ "$1" = "api" ] && [ "$2" = "repos/acme/widgets/issues/42/comments" ] && [ "$3" = "--method" ] && [ "$4" = "POST" ]; then
          printf '{"id":56,"body":"[codex] acknowledged","user":{"login":"codex","type":"Bot"}}\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert {"55\n", "", 0} =
                 RepoProviderCLI.evaluate(["pr-issue-comments", "42", "--json", "id,body", "-q", ".[0].id"], deps)

        {output, "", 0} =
          RepoProviderCLI.evaluate(
            ["pr-add-issue-comment", "42", "--body", "[codex] acknowledged"],
            deps
          )

        assert Jason.decode!(output)["id"] == 56
        assert Jason.decode!(output)["body"] == "[codex] acknowledged"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "github run-list and run-view log return normalized output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-github-runs-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_path = Path.join(bin_dir, "gh")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)

      write_executable!(
        gh_path,
        """
        #!/bin/sh
        if [ "$1" = "run" ] && [ "$2" = "list" ]; then
          printf '[{"databaseId":24870399231,"displayTitle":"Triage Scheduled Tasks","status":"completed","conclusion":"success","headBranch":"trunk","headSha":"352a00e83c1c0a9723c5fb863db1fa65157e4d2a","event":"schedule","createdAt":"2026-04-24T03:17:24Z","updatedAt":"2026-04-24T03:17:36Z","url":"https://github.com/acme/widgets/actions/runs/24870399231","workflowName":"Triage Scheduled Tasks","number":101,"attempt":1}]\\n'
          exit 0
        fi
        if [ "$1" = "run" ] && [ "$2" = "view" ] && [ "$6" = "--json" ]; then
          printf '{"databaseId":24870399231,"displayTitle":"Triage Scheduled Tasks","status":"completed","conclusion":"success","headBranch":"trunk","headSha":"352a00e83c1c0a9723c5fb863db1fa65157e4d2a","event":"schedule","createdAt":"2026-04-24T03:17:24Z","startedAt":"2026-04-24T03:17:25Z","updatedAt":"2026-04-24T03:17:36Z","url":"https://github.com/acme/widgets/actions/runs/24870399231","workflowName":"Triage Scheduled Tasks","number":101,"attempt":1,"jobs":[{"databaseId":72815466837,"name":"no-response / noResponse","status":"completed","conclusion":"success","startedAt":"2026-04-24T03:17:28Z","completedAt":"2026-04-24T03:17:35Z","url":"https://github.com/acme/widgets/actions/runs/24870399231/job/72815466837","steps":[{"number":1,"name":"Set up job","status":"completed","conclusion":"success","startedAt":"2026-04-24T03:17:29Z","completedAt":"2026-04-24T03:17:30Z"}]}]}\\n'
          exit 0
        fi
        if [ "$1" = "run" ] && [ "$2" = "view" ] && [ "$6" = "--log" ]; then
          printf 'job-1\\tUNKNOWN STEP\\t2026-04-24T03:17:29Z Starting\\n'
          exit 0
        fi
        printf 'unexpected gh invocation: %s\\n' "$*" >&2
        exit 99
        """
      )

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "github",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets"
        })

      with_env(%{"PATH" => Enum.join([bin_dir, System.get_env("PATH") || ""], ":")}, fn ->
        assert {"24870399231\n", "", 0} =
                 RepoProviderCLI.evaluate(["run-list", "--branch", "trunk", "--json", "id", "-q", ".[0].id"], deps)

        {output, "", 0} = RepoProviderCLI.evaluate(["run-view", "24870399231", "--log"], deps)
        assert output =~ "Run 24870399231: success"
        assert output =~ "Workflow: Triage Scheduled Tasks"
        assert output =~ "job-1\tUNKNOWN STEP"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb auth-status and pr-view work through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        assert {"CNB auth ok as tester\n", "", 0} =
                 RepoProviderCLI.evaluate(["auth-status"], deps)

        File.cd!(root, fn ->
          assert {"https://cnb.cool/acme/widgets/-/pulls/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-view", "--json", "url", "-q", ".url"], deps)
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb api supports nested repository paths through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-api-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "example-org/AI/sample-cnb-project",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"reviewer\n", "", 0} =
                   RepoProviderCLI.evaluate(
                     [
                       "api",
                       "repos/example-org/AI/sample-cnb-project/issues/42/comments",
                       "--method",
                       "GET",
                       "-F",
                       "page=1",
                       "-F",
                       "per_page=2",
                       "-q",
                       ".[0].user.login"
                     ],
                     deps
                   )
        end)
      end)

      assert_receive {:cli_cnb_request,
                      %{
                        method: "GET",
                        path: "/example-org%2FAI%2Fsample-cnb-project/-/pulls/42/comments",
                        query: %{"page" => "1", "page_size" => "2"}
                      }}
    after
      File.rm_rf!(root)
    end
  end

  test "cnb run-list and run-view log work through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-runs-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"1001\n", "", 0} =
                   RepoProviderCLI.evaluate(
                     ["run-list", "--branch", "feature/cnb-provider", "--json", "id,headSha,url", "-q", ".[0].id"],
                     deps
                   )

          {output, "", 0} = RepoProviderCLI.evaluate(["run-view", "1001", "--log"], deps)

          assert output =~ "Run 1001: success"
          assert output =~ "== Pipeline ci (success) =="
          assert output =~ "-- Stage checkout (success) --"
          assert output =~ "80 tests, 0 failures"
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb run-list surfaces actionable build-scope errors through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-run-scope-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!(:build_scope_forbidden)

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"", stderr, 1} =
                   RepoProviderCLI.evaluate(
                     ["run-list", "--branch", "feature/cnb-provider", "--json", "id", "-q", ".[0].id"],
                     deps
                   )

          assert stderr =~ "Grant CNB build authorization"
          assert stderr =~ "current CNB_TOKEN cannot access run data"
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb pr-create, pr-edit, pr-close, and pr-merge work through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-mutations-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool",
          "SYMPHONY_REPO_BASE_BRANCH" => "main"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"https://cnb.cool/acme/widgets/-/pulls/42\n", "", 0} =
                   RepoProviderCLI.evaluate(
                     ["pr-create", "--title", "Add CNB provider support", "--body", "Implements the first CNB slice"],
                     deps
                   )

          assert_receive {:cli_cnb_request,
                          %{
                            method: "POST",
                            path: "/acme%2Fwidgets/-/pulls",
                            body: create_body
                          }}

          assert Jason.decode!(create_body) == %{
                   "base" => "main",
                   "body" => "Implements the first CNB slice",
                   "head" => "feature/cnb-provider",
                   "title" => "Add CNB provider support"
                 }

          assert {"https://cnb.cool/acme/widgets/-/pulls/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-edit", "42", "--title", "Updated title"], deps)

          assert_receive {:cli_cnb_request,
                          %{
                            method: "PATCH",
                            path: "/acme%2Fwidgets/-/pulls/42",
                            body: edit_body
                          }}

          assert Jason.decode!(edit_body) == %{"title" => "Updated title"}

          assert {"https://cnb.cool/acme/widgets/-/pulls/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-merge", "42", "--squash", "--subject", "Ship it", "--body", "Merged by CLI"], deps)

          assert_receive {:cli_cnb_request,
                          %{
                            method: "PUT",
                            path: "/acme%2Fwidgets/-/pulls/42/merge",
                            body: merge_body
                          }}

          assert Jason.decode!(merge_body) == %{
                   "commit_message" => "Merged by CLI",
                   "commit_title" => "Ship it",
                   "merge_style" => "squash"
                 }

          assert {"https://cnb.cool/acme/widgets/-/pulls/42\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-close", "42"], deps)

          assert_receive {:cli_cnb_request,
                          %{
                            method: "PATCH",
                            path: "/acme%2Fwidgets/-/pulls/42",
                            body: close_body
                          }}

          assert Jason.decode!(close_body) == %{"state" => "closed"}
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb review comment commands work through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-review-comments-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"101\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-review-comments", "42", "--json", "id", "-q", ".[0].id"], deps)

          {output, "", 0} =
            RepoProviderCLI.evaluate(
              ["pr-reply-review-comment", "101", "42", "--body", "[codex] acknowledged"],
              deps
            )

          reply = Jason.decode!(output)
          assert reply["id"] == "102"
          assert reply["in_reply_to_id"] == "101"

          assert_receive {:cli_cnb_request,
                          %{
                            method: "POST",
                            path: "/acme%2Fwidgets/-/pulls/42/reviews/9/replies",
                            body: reply_body
                          }}

          assert Jason.decode!(reply_body) == %{
                   "body" => "[codex] acknowledged",
                   "reply_to_comment_id" => "101"
                 }
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb pr-reviews works through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-reviews-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"APPROVED\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-reviews", "42", "--json", "state", "-q", ".[0].state"], deps)
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb issue comment commands work through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-issue-comments-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"55\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-issue-comments", "42", "--json", "id", "-q", ".[0].id"], deps)

          {output, "", 0} =
            RepoProviderCLI.evaluate(
              ["pr-add-issue-comment", "42", "--body", "[codex] acknowledged"],
              deps
            )

          comment = Jason.decode!(output)
          assert comment["id"] == "56"
          assert comment["body"] == "[codex] acknowledged"

          assert_receive {:cli_cnb_request,
                          %{
                            method: "POST",
                            path: "/acme%2Fwidgets/-/pulls/42/comments",
                            body: request_body
                          }}

          assert Jason.decode!(request_body) == %{"body" => "[codex] acknowledged"}
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "cnb pr-checks returns normalized JSON, text summaries, and watch output through the Elixir CLI path" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-cli-cnb-checks-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      init_git_repo!(root)
      api_base_url = start_test_server!()

      deps =
        cli_deps(%{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => api_base_url,
          "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
        })

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          assert {"ci: completed/success (green)\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-checks"], deps)

          assert {"ci\n", "", 0} =
                   RepoProviderCLI.evaluate(["pr-checks", "--json", "-q", ".[0].name"], deps)
        end)
      end)

      watch_counter = start_supervised!({Agent, fn -> 0 end})
      watch_api_base_url = start_test_server!({:checks_sequence, watch_counter})

      watch_deps =
        Map.put(deps, :env, fn ->
          %{
            "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
            "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
            "SYMPHONY_REPO_PROVIDER_API_BASE_URL" => watch_api_base_url,
            "SYMPHONY_REPO_PROVIDER_WEB_BASE_URL" => "https://cnb.cool"
          }
        end)

      with_env(%{"CNB_TOKEN" => "test-token"}, fn ->
        File.cd!(root, fn ->
          {output, "", 0} =
            RepoProviderCLI.evaluate(
              ["pr-checks", "--watch", "--json", "-q", ".[0].conclusion"],
              Map.put(watch_deps, :command_opts, fn -> [watch_poll_ms: 0, sleep_fn: fn _ms -> :ok end] end)
            )

          assert output == "null\nsuccess\n"
        end)
      end)
    after
      File.rm_rf!(root)
    end
  end

  defp start_test_server!(mode \\ :success) do
    pid =
      start_supervised!({Bandit, plug: {TestPlug, owner: self(), mode: mode}, scheme: :http, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}"
  end

  defp cli_deps(env) do
    %{
      env: fn -> env end,
      stdout: fn _output -> :ok end,
      stderr: fn _output -> :ok end,
      halt: fn _status -> raise "halt should not be called from evaluate/2" end
    }
  end

  defp init_git_repo!(root) do
    {_, 0} = CommandEnv.system_cmd("git", ["init", "--initial-branch=main"], cd: root)
    File.write!(Path.join(root, "README.md"), "cli test\n")
    {_, 0} = CommandEnv.system_cmd("git", ["add", "README.md"], cd: root)

    {_, 0} =
      CommandEnv.system_cmd(
        "git",
        ["-c", "user.name=Test User", "-c", "user.email=test@example.com", "commit", "-m", "init"],
        cd: root
      )

    {_, 0} = CommandEnv.system_cmd("git", ["checkout", "-b", "feature/cnb-provider"], cd: root)
    {_, 0} = CommandEnv.system_cmd("git", ["remote", "add", "origin", "https://cnb.cool/acme/widgets.git"], cd: root)
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
end
