defmodule SymphonyElixir.RepoProviderSmokeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SymphonyElixir.RepoProvider.Smoke

  test "smoke runs explicit GitHub PR probes and emits observability events" do
    parent = self()

    deps = %{
      env: fn -> %{} end,
      command_opts: fn -> [] end,
      cli_evaluate: fn argv, _cli_deps ->
        case argv do
          ["--provider", "github", "current-kind"] ->
            {"github\n", "", 0}

          ["--provider", "github", "auth-status"] ->
            {"Logged in to github.com as smoke-user\n", "", 0}

          ["--provider", "github", "pr-view", "42", "--json", "url", "-q", ".url"] ->
            {"https://github.com/acme/widgets/pull/42\n", "", 0}

          ["--provider", "github", "pr-reviews", "42", "--json", "state", "-q", ".[0].state"] ->
            {"APPROVED\n", "", 0}

          ["--provider", "github", "pr-checks", "42"] ->
            {"ci: completed/success (green)\n", "", 0}

          other ->
            flunk("unexpected smoke probe argv: #{inspect(other)}")
        end
      end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: fn level, event, fields ->
        send(parent, {:smoke_event, level, event, fields})
        fields
      end
    }

    report =
      capture_log(fn ->
        report = Smoke.run([provider: "github", repo: "acme/widgets", pr: "42"], deps)
        assert report.ok
        assert report.smoke_mode == "read_only"
        assert report.provider_kind == "github"
        assert report.repo_provider_runtime == "symphony"
        assert report.repository == "acme/widgets"
        assert report.probe_count == 5
        assert report.passed_count == 5

        assert Enum.map(report.probes, & &1.id) == [
                 "current-kind",
                 "auth-status",
                 "pr-view",
                 "pr-reviews",
                 "pr-checks"
               ]

        report
      end)

    assert is_binary(report)

    assert_received {:smoke_event, :info, :repo_provider_smoke_started, started}
    assert_received {:smoke_event, :info, :repo_provider_smoke_finished, finished}

    assert started.component == "repo_provider.smoke"
    assert started.provider_kind == "github"
    assert started.repo_provider_runtime == "symphony"
    assert started.smoke_mode == "read_only"
    assert started.repository == "acme/widgets"
    assert started.probe_count == 5

    assert finished.component == "repo_provider.smoke"
    assert finished.provider_kind == "github"
    assert finished.repo_provider_runtime == "symphony"
    assert finished.smoke_mode == "read_only"
    assert finished.repository == "acme/widgets"
    assert finished.status == "ok"
    assert finished.probe_count == 5
    assert finished.passed_count == 5
    assert finished.failed_count == 0
    assert finished.exit_code == 0
  end

  test "smoke reports failures in text output" do
    deps = %{
      env: fn ->
        %{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb"
        }
      end,
      command_opts: fn -> [] end,
      cli_evaluate: fn argv, _cli_deps ->
        case argv do
          ["current-kind"] ->
            {"cnb\n", "", 0}

          ["auth-status"] ->
            {"CNB auth ok as tester\n", "", 0}

          ["api", "repos/{owner}/{repo}/issues/42/comments", "-q", ".[0].id"] ->
            {"", "CNB api failed\n", 1}

          other ->
            flunk("unexpected smoke probe argv: #{inspect(other)}")
        end
      end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: fn _level, _event, fields -> fields end
    }

    report =
      capture_log(fn ->
        Smoke.run([api_endpoint: "repos/{owner}/{repo}/issues/42/comments", api_jq: ".[0].id"], deps)
      end)

    assert is_binary(report)

    smoke_report =
      Smoke.run(
        [api_endpoint: "repos/{owner}/{repo}/issues/42/comments", api_jq: ".[0].id"],
        Map.put(deps, :emit_event, fn _level, _event, _fields -> %{} end)
      )

    refute smoke_report.ok
    assert smoke_report.failed_count == 1

    text = Smoke.format_text(smoke_report)
    assert text =~ "repo-provider smoke failed provider=cnb runtime=symphony mode=read_only probes=3 passed=2 failed=1"
    assert text =~ "FAIL api exit=1"
    assert text =~ ~s(summary="CNB api failed")
  end

  test "destructive smoke creates, edits, verifies, and closes a PR" do
    created_url = "https://github.com/acme/widgets/pull/77"
    create_body = "Initial destructive smoke body"
    edited_body = create_body <> "\n\nEdited by Symphony repo-provider destructive smoke."
    {:ok, state_ref} = Agent.start_link(fn -> %{body: create_body, state: "OPEN"} end)

    deps = %{
      env: fn -> %{} end,
      command_opts: fn -> [] end,
      cli_evaluate: fn argv, _cli_deps ->
        case argv do
          ["--provider", "github", "current-kind"] ->
            {"github\n", "", 0}

          ["--provider", "github", "auth-status"] ->
            {"Logged in to github.com as smoke-user\n", "", 0}

          [
            "--provider",
            "github",
            "pr-create",
            "--title",
            "Destructive smoke",
            "--body",
            ^create_body,
            "--base",
            "main",
            "--head",
            "feature/destructive-smoke"
          ] ->
            {created_url <> "\n", "", 0}

          ["--provider", "github", "pr-view", "77", "--json", "url", "-q", ".url"] ->
            {created_url <> "\n", "", 0}

          ["--provider", "github", "pr-edit", "77", "--body", ^edited_body] ->
            Agent.update(state_ref, &Map.put(&1, :body, edited_body))
            {created_url <> "\n", "", 0}

          ["--provider", "github", "pr-view", "77", "--json", "body", "-q", ".body"] ->
            {Agent.get(state_ref, & &1.body) <> "\n", "", 0}

          ["--provider", "github", "pr-close", "77"] ->
            Agent.update(state_ref, &Map.put(&1, :state, "CLOSED"))
            {created_url <> "\n", "", 0}

          ["--provider", "github", "pr-view", "77", "--json", "state", "-q", ".state"] ->
            {Agent.get(state_ref, & &1.state) <> "\n", "", 0}

          other ->
            flunk("unexpected destructive smoke probe argv: #{inspect(other)}")
        end
      end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: fn _level, _event, fields -> fields end
    }

    capture_log(fn ->
      report =
        Smoke.run(
          [
            provider: "github",
            repo: "acme/widgets",
            destructive: true,
            head: "feature/destructive-smoke",
            base: "main",
            title: "Destructive smoke",
            body: create_body
          ],
          deps
        )

      assert report.ok
      assert report.smoke_mode == "destructive"
      assert report.probe_count == 8

      assert Enum.map(report.probes, & &1.id) == [
               "current-kind",
               "auth-status",
               "pr-create",
               "pr-view-created",
               "pr-edit",
               "pr-view-edited",
               "pr-close",
               "pr-view-closed"
             ]
    end)
  end

  test "destructive smoke still closes the PR after verification failures" do
    created_url = "https://cnb.cool/acme/widgets/-/pulls/42"
    create_body = "Initial destructive smoke body"
    edited_body = create_body <> "\n\nEdited by Symphony repo-provider destructive smoke."
    {:ok, call_log} = Agent.start_link(fn -> [] end)
    {:ok, state_ref} = Agent.start_link(fn -> %{body: create_body, state: "OPEN"} end)

    deps = %{
      env: fn ->
        %{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb"
        }
      end,
      command_opts: fn -> [] end,
      cli_evaluate: fn argv, _cli_deps ->
        Agent.update(call_log, &(&1 ++ [argv]))

        case argv do
          ["current-kind"] ->
            {"cnb\n", "", 0}

          ["auth-status"] ->
            {"CNB auth ok as tester\n", "", 0}

          [
            "pr-create",
            "--title",
            "Repo-provider destructive smoke for feature/smoke -> main",
            "--body",
            ^create_body,
            "--base",
            "main",
            "--head",
            "feature/smoke"
          ] ->
            {created_url <> "\n", "", 0}

          ["pr-view", "42", "--json", "url", "-q", ".url"] ->
            {created_url <> "\n", "", 0}

          ["pr-edit", "42", "--body", ^edited_body] ->
            Agent.update(state_ref, &Map.put(&1, :body, "stale body"))
            {created_url <> "\n", "", 0}

          ["pr-view", "42", "--json", "body", "-q", ".body"] ->
            {Agent.get(state_ref, & &1.body) <> "\n", "", 0}

          ["pr-close", "42"] ->
            Agent.update(state_ref, &Map.put(&1, :state, "CLOSED"))
            {created_url <> "\n", "", 0}

          ["pr-view", "42", "--json", "state", "-q", ".state"] ->
            {Agent.get(state_ref, & &1.state) <> "\n", "", 0}

          other ->
            flunk("unexpected destructive cleanup probe argv: #{inspect(other)}")
        end
      end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: fn _level, _event, _fields -> %{} end
    }

    report =
      Smoke.run(
        [
          destructive: true,
          head: "feature/smoke",
          base: "main",
          body: create_body
        ],
        deps
      )

    refute report.ok
    assert report.failed_count == 1

    assert Enum.find(report.probes, &(&1.id == "pr-view-edited")).summary =~ "Expected stdout"
    assert Enum.find(report.probes, &(&1.id == "pr-close")).ok
    assert Enum.find(report.probes, &(&1.id == "pr-view-closed")).ok

    assert Agent.get(call_log, & &1) == [
             ["current-kind"],
             ["auth-status"],
             ["pr-create", "--title", "Repo-provider destructive smoke for feature/smoke -> main", "--body", create_body, "--base", "main", "--head", "feature/smoke"],
             ["pr-view", "42", "--json", "url", "-q", ".url"],
             ["pr-edit", "42", "--body", edited_body],
             ["pr-view", "42", "--json", "body", "-q", ".body"],
             ["pr-close", "42"],
             ["pr-view", "42", "--json", "state", "-q", ".state"]
           ]
  end

  test "CNB auto-provision destructive smoke validates run surfaces and cleans up" do
    parent = self()
    created_url = "https://cnb.cool/acme/widgets/-/pulls/88"
    temp_dir = "/tmp/repo-provider-cnb-smoke"
    worktree = Path.join(temp_dir, "repo")
    {:ok, call_log} = Agent.start_link(fn -> %{cli: [], git: [], writes: []} end)
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    {:ok, state_ref} = Agent.start_link(fn -> %{head: nil, edited_body: nil} end)
    {:ok, run_attempts} = Agent.start_link(fn -> 0 end)
    {:ok, run_log_attempts} = Agent.start_link(fn -> 0 end)

    deps = %{
      env: fn ->
        %{
          "SYMPHONY_REPO_PROVIDER_KIND" => "cnb",
          "SYMPHONY_REPO_PROVIDER_REPOSITORY" => "acme/widgets",
          "CNB_TOKEN" => "test-token"
        }
      end,
      command_opts: fn -> [] end,
      cli_evaluate: fn argv, _cli_deps ->
        Agent.update(call_log, &Map.update!(&1, :cli, fn calls -> calls ++ [argv] end))

        case argv do
          ["current-kind"] ->
            {"cnb\n", "", 0}

          ["auth-status"] ->
            {"CNB auth ok as tester\n", "", 0}

          ["pr-create", "--title", title, "--body", body, "--base", "main", "--head", head]
          when is_binary(head) ->
            assert String.starts_with?(head, "repo-provider-smoke/cnb-pipeline-")
            assert title == "Repo-provider CNB auto-provision smoke for #{head} -> main"
            assert body =~ "Mode: auto-provision-cnb-pipeline"
            assert body =~ "Head: #{head}"
            assert body =~ "Base: main"
            {created_url <> "\n", "", 0}

          ["pr-view", "88", "--json", "url", "-q", ".url"] ->
            {created_url <> "\n", "", 0}

          ["pr-edit", "88", "--body", edited_body] ->
            assert edited_body =~ "Edited by Symphony repo-provider destructive smoke."
            Agent.update(state_ref, &Map.put(&1, :edited_body, edited_body))
            {created_url <> "\n", "", 0}

          ["pr-view", "88", "--json", "body", "-q", ".body"] ->
            {Agent.get(state_ref, & &1.edited_body) <> "\n", "", 0}

          ["run-list", "--branch", head, "--json", "id,event,status,url"] ->
            assert head == Agent.get(state_ref, & &1.head)

            current_attempt =
              Agent.get_and_update(run_attempts, fn attempts ->
                {attempts, attempts + 1}
              end)

            payload =
              if current_attempt == 0 do
                []
              else
                [
                  %{"id" => "cnb-push-1", "event" => "push", "status" => "success", "url" => "https://cnb.cool/acme/widgets/-/build/logs/cnb-push-1"},
                  %{"id" => "cnb-pr-1", "event" => "pull_request", "status" => "success", "url" => "https://cnb.cool/acme/widgets/-/build/logs/cnb-pr-1"}
                ]
              end

            {Jason.encode!(payload) <> "\n", "", 0}

          ["run-view", "cnb-pr-1", "--log"] ->
            current_attempt =
              Agent.get_and_update(run_log_attempts, fn attempts ->
                {attempts, attempts + 1}
              end)

            if current_attempt == 0 do
              {"Run still starting\n", "", 0}
            else
              {"repo-provider probe pull_request\nbranch=repo-provider-smoke\n", "", 0}
            end

          ["pr-close", "88"] ->
            {created_url <> "\n", "", 0}

          ["pr-view", "88", "--json", "state", "-q", ".state"] ->
            {"CLOSED\n", "", 0}

          other ->
            flunk("unexpected auto-provision CLI argv: #{inspect(other)}")
        end
      end,
      monotonic_time_ms: fn ->
        Agent.get_and_update(clock, fn value ->
          {value, value + 1_000}
        end)
      end,
      emit_event: fn _level, _event, fields -> fields end,
      mk_temp_dir: fn prefix ->
        assert prefix == "repo-provider-cnb-smoke"
        File.mkdir_p!(temp_dir)
        {:ok, temp_dir}
      end,
      write_file: fn path, contents ->
        Agent.update(call_log, &Map.update!(&1, :writes, fn calls -> calls ++ [{path, contents}] end))
        assert path == Path.join(worktree, ".cnb.yml")
        assert contents =~ "repo-provider probe pull_request"
        assert contents =~ "# smoke_branch=#{Agent.get(state_ref, & &1.head)}"
        :ok
      end,
      rm_rf: fn path ->
        send(parent, {:rm_rf, path})
        File.rm_rf(path)
        :ok
      end,
      sleep_ms: fn milliseconds ->
        send(parent, {:sleep_ms, milliseconds})
        :ok
      end,
      system_cmd: fn "git", argv, _opts ->
        Agent.update(call_log, &Map.update!(&1, :git, fn calls -> calls ++ [argv] end))

        case argv do
          ["-c", header, "clone", "--depth", "1", "--branch", "main", "https://cnb.cool/acme/widgets.git", ^worktree] ->
            assert String.starts_with?(header, "http.extraHeader=Authorization: Basic ")
            File.mkdir_p!(worktree)
            {"cloned\n", 0}

          ["-C", ^worktree, "switch", "-c", head, "HEAD"] ->
            assert String.starts_with?(head, "repo-provider-smoke/cnb-pipeline-")
            Agent.update(state_ref, &Map.put(&1, :head, head))
            {"switched\n", 0}

          ["-C", ^worktree, "rev-parse", "--show-toplevel"] ->
            {worktree <> "\n", 0}

          ["-C", ^worktree, "status", "--porcelain=v1", "-z", "--untracked-files=all"] ->
            {"?? .cnb.yml" <> <<0>>, 0}

          ["-C", ^worktree, "branch", "--show-current"] ->
            {Agent.get(state_ref, & &1.head) <> "\n", 0}

          ["-C", ^worktree, "rev-parse", "HEAD"] ->
            {"0123456789abcdef0123456789abcdef01234567\n", 0}

          ["-C", ^worktree, "add", "-A"] ->
            {"added\n", 0}

          [
            "-C",
            ^worktree,
            "-c",
            "user.name=Symphony Smoke",
            "-c",
            "user.email=repo-provider-smoke@example.invalid",
            "commit",
            "-m",
            "repo-provider smoke: auto-provision temporary .cnb.yml"
          ] ->
            {"committed\n", 0}

          ["-C", ^worktree, "-c", header, "push", "-u", "origin", head] ->
            assert String.starts_with?(header, "http.extraHeader=Authorization: Basic ")
            assert head == Agent.get(state_ref, & &1.head)
            {"pushed\n", 0}

          ["-C", ^worktree, "-c", header, "push", "origin", "--delete", head] ->
            assert String.starts_with?(header, "http.extraHeader=Authorization: Basic ")
            assert head == Agent.get(state_ref, & &1.head)
            {"deleted\n", 0}

          other ->
            flunk("unexpected git auto-provision argv: #{inspect(other)}")
        end
      end
    }

    report =
      Smoke.run(
        [
          destructive: true,
          auto_provision_cnb_pipeline: true,
          base: "main"
        ],
        deps
      )

    assert report.ok
    assert report.smoke_mode == "destructive_auto_provision_cnb_pipeline"
    assert report.probe_count == 14
    assert report.passed_count == 14

    assert Enum.map(report.probes, & &1.id) == [
             "current-kind",
             "auth-status",
             "git-clone",
             "git-prepare-cnb-pipeline",
             "git-push-cnb-pipeline",
             "pr-create",
             "pr-view-created",
             "pr-edit",
             "pr-view-edited",
             "run-list",
             "run-view-log",
             "pr-close",
             "pr-view-closed",
             "git-delete-cnb-pipeline-branch"
           ]

    assert Enum.find(report.probes, &(&1.id == "run-list")).summary ==
             "observed events=push,pull_request selected_run=cnb-pr-1"

    log = Agent.get(call_log, & &1)
    assert length(log.writes) == 1
    assert length(log.git) == 12
    assert length(log.cli) == 12

    assert_received {:sleep_ms, 5_000}
    assert_received {:sleep_ms, 5_000}
    assert_received {:rm_rf, ^temp_dir}
  end
end
