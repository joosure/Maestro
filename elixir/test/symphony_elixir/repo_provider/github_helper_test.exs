defmodule SymphonyElixir.RepoProvider.GitHubHelperTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.TestSupport.Snapshot
  alias SymphonyElixir.Workspace.AutomationPack

  test "bundled helper routes GitHub commands through symphony and forwards repository env" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf 'REPO=%s CMD=%s\\n' "${SYMPHONY_REPO_PROVIDER_REPOSITORY:-}" "$*" >> "$SYMPHONY_LOG"
      printf 'https://example.test/pr/123\\n'
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        {output, 0} =
          System.cmd(
            helper,
            ["pr-view", "--json", "url", "-q", ".url"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
            ],
            stderr_to_stdout: true
          )

        Snapshot.assert_snapshot!("repo_provider_contract/github/pr_view_url.stdout.txt", output)

        log = File.read!(log_path)
        assert log =~ "REPO=acme/widgets"
        assert log =~ "repo-provider --provider github pr-view --json url -q .url"
      end
    )
  end

  test "bundled helper preserves the top-level usage contract" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-usage-test-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      {output, status} =
        System.cmd(
          helper,
          [],
          env: [{"PATH", System.get_env("PATH") || ""}],
          stderr_to_stdout: true
        )

      assert status == 64
      Snapshot.assert_snapshot!("repo_provider_contract/top_level_usage.output.txt", output)
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper rejects unknown providers explicitly" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-unsupported-provider-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      {output, status} =
        System.cmd(
          helper,
          ["--provider", "gitlab", "pr-view"],
          env: [{"PATH", System.get_env("PATH") || ""}],
          stderr_to_stdout: true
        )

      assert status == 64
      assert output =~ "Unsupported repo provider: gitlab"
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper fails fast with a clear message when symphony is unavailable" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-missing-symphony-#{unique}")
    bash = System.find_executable("bash")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      {output, status} =
        System.cmd(
          bash,
          [helper, "pr-view"],
          env: [{"PATH", ""}],
          stderr_to_stdout: true
        )

      assert status == 64
      assert output =~ "repo-provider helper requires executable SYMPHONY_CLI or symphony in PATH"
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper honors SYMPHONY_CLI when symphony is not in PATH" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-symphony-cli-#{unique}")
    log_path = Path.join(root, "symphony.log")
    bash = System.find_executable("bash")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      File.write!(log_path, "")
      helper = copy_helper!(root)

      symphony_cli = Path.join(root, "symphony-cli")

      write_executable!(
        symphony_cli,
        """
        #!/bin/sh
        printf 'REPO=%s CMD=%s\\n' "${SYMPHONY_REPO_PROVIDER_REPOSITORY:-}" "$*" >> "$SYMPHONY_LOG"
        printf '%s\\n' "$3"
        """
      )

      assert {"cnb\n", 0} =
               System.cmd(bash, [helper, "current-kind"],
                 env: [
                   {"PATH", ""},
                   {"SYMPHONY_CLI", symphony_cli},
                   {"SOURCE_REPO_PROVIDER_KIND", "cnb"},
                   {"SOURCE_REPO_PROVIDER_REPOSITORY", "acme/widgets"},
                   {"SYMPHONY_LOG", log_path}
                 ],
                 stderr_to_stdout: true
               )

      log = File.read!(log_path)
      assert log =~ "REPO=acme/widgets"
      assert log =~ "repo-provider --provider cnb current-kind"
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper preserves the top-level provider contract for current-kind" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$3"
      """,
      fn root, _log_path ->
        helper = copy_helper!(root)

        {default_output, 0} =
          System.cmd(
            helper,
            ["current-kind"],
            env: [{"PATH", path_with_bin(root)}],
            stderr_to_stdout: true
          )

        Snapshot.assert_snapshot!("repo_provider_contract/current_kind/github.stdout.txt", default_output)

        {explicit_output, 0} =
          System.cmd(
            helper,
            ["current-kind"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SYMPHONY_REPO_PROVIDER_KIND", "cnb"}
            ],
            stderr_to_stdout: true
          )

        Snapshot.assert_snapshot!("repo_provider_contract/current_kind/cnb.stdout.txt", explicit_output)

        {source_alias_output, 0} =
          System.cmd(
            helper,
            ["current-kind"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SOURCE_REPO_PROVIDER_KIND", "cnb"}
            ],
            stderr_to_stdout: true
          )

        Snapshot.assert_snapshot!("repo_provider_contract/current_kind/cnb.stdout.txt", source_alias_output)
      end
    )
  end

  test "bundled helper routes current-kind through symphony when available" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf '%s\\n' "$3"
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        {output, 0} =
          System.cmd(
            helper,
            ["current-kind"],
            env: [{"PATH", path_with_bin(root)}],
            stderr_to_stdout: true
          )

        assert output == "github\n"
        assert File.read!(log_path) =~ "repo-provider --provider github current-kind"
      end
    )
  end

  test "bundled helper routes GitHub pr-view through symphony without invoking gh" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-github-pr-view-#{unique}")
    bin_dir = Path.join(root, "bin")
    gh_log_path = Path.join(root, "gh.log")
    symphony_log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      File.write!(gh_log_path, "")
      File.write!(symphony_log_path, "")
      helper = copy_helper!(root)

      write_executable!(
        Path.join(bin_dir, "gh"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$GH_LOG"
        printf 'unexpected gh invocation\\n' >&2
        exit 88
        """
      )

      write_executable!(
        Path.join(bin_dir, "symphony"),
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'https://example.test/pr/123\\n'
        """
      )

      with_env(%{"GH_LOG" => gh_log_path, "SYMPHONY_LOG" => symphony_log_path}, fn ->
        {output, 0} =
          System.cmd(
            helper,
            ["pr-view", "--json", "url", "-q", ".url"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
            ],
            stderr_to_stdout: true
          )

        assert output == "https://example.test/pr/123\n"
        assert File.read!(gh_log_path) == ""
        assert File.read!(symphony_log_path) =~ "repo-provider --provider github pr-view --json url -q .url"
      end)
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper routes GitHub pr-checks and PR writes through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      case "$*" in
        *"pr-checks"*) printf 'ci: completed/success (green)\\n' ;;
        *"pr-land-watch"*) printf 'Checks passed\\n' ;;
        *) printf 'https://github.com/acme/widgets/pull/42\\n' ;;
      esac
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        env = [
          {"PATH", path_with_bin(root)},
          {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
        ]

        for args <- [
              ["pr-create", "--title", "Add GitHub provider support"],
              ["pr-edit", "42", "--body", "updated"],
              ["pr-add-label", "release-ready", "42"],
              ["pr-checks", "--watch"],
              ["pr-land-watch"],
              ["pr-merge", "42", "--squash"],
              ["pr-close", "42", "--comment", "[codex] restarting from a fresh branch"]
            ] do
          {output, 0} = System.cmd(helper, args, env: env, stderr_to_stdout: true)
          assert output in ["https://github.com/acme/widgets/pull/42\n", "ci: completed/success (green)\n", "Checks passed\n"]
        end

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider github pr-create --title Add GitHub provider support"
        assert log =~ "repo-provider --provider github pr-edit 42 --body updated"
        assert log =~ "repo-provider --provider github pr-add-label release-ready 42"
        assert log =~ "repo-provider --provider github pr-checks --watch"
        assert log =~ "repo-provider --provider github pr-land-watch"
        assert log =~ "repo-provider --provider github pr-merge 42 --squash"
        assert log =~ "repo-provider --provider github pr-close 42 --comment [codex] restarting from a fresh branch"
      end
    )
  end

  test "bundled helper routes GitHub api through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf 'acme/widgets\\n'
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        {output, 0} =
          System.cmd(
            helper,
            ["api", "repos/{owner}/{repo}", "-q", ".full_name"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
            ],
            stderr_to_stdout: true
          )

        assert output == "acme/widgets\n"
        assert File.read!(log_path) =~ "repo-provider --provider github api repos/{owner}/{repo} -q .full_name"
      end
    )
  end

  test "bundled helper routes GitHub review comment commands through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      case "$*" in
        *"pr-review-comments"*) printf '[{"id":101,"body":"inline note"}]\\n' ;;
        *"pr-reply-review-comment"*) printf '{"id":102,"body":"[codex] acknowledged","in_reply_to_id":101}\\n' ;;
        *) printf 'unexpected command\\n' >&2; exit 87 ;;
      esac
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        env = [
          {"PATH", path_with_bin(root)},
          {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
        ]

        {list_output, 0} =
          System.cmd(helper, ["pr-review-comments", "42"], env: env, stderr_to_stdout: true)

        {reply_output, 0} =
          System.cmd(
            helper,
            ["pr-reply-review-comment", "101", "42", "--body", "[codex] acknowledged"],
            env: env,
            stderr_to_stdout: true
          )

        assert Jason.decode!(list_output) |> List.first() |> Map.fetch!("id") == 101
        assert Jason.decode!(reply_output)["in_reply_to_id"] == 101

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider github pr-review-comments 42"
        assert log =~ "repo-provider --provider github pr-reply-review-comment 101 42 --body [codex] acknowledged"
      end
    )
  end

  test "bundled helper routes GitHub pr-reviews through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf '[{"id":9,"state":"APPROVED"}]\\n'
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        {output, 0} =
          System.cmd(
            helper,
            ["pr-reviews", "42"],
            env: [
              {"PATH", path_with_bin(root)},
              {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
            ],
            stderr_to_stdout: true
          )

        assert Jason.decode!(output) |> List.first() |> Map.fetch!("state") == "APPROVED"
        assert File.read!(log_path) =~ "repo-provider --provider github pr-reviews 42"
      end
    )
  end

  test "bundled helper routes GitHub issue comment commands through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      case "$*" in
        *"pr-issue-comments"*) printf '[{"id":55,"body":"top-level note"}]\\n' ;;
        *"pr-add-issue-comment"*) printf '{"id":56,"body":"[codex] acknowledged"}\\n' ;;
        *) printf 'unexpected command\\n' >&2; exit 87 ;;
      esac
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        env = [
          {"PATH", path_with_bin(root)},
          {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
        ]

        {list_output, 0} =
          System.cmd(helper, ["pr-issue-comments", "42"], env: env, stderr_to_stdout: true)

        {create_output, 0} =
          System.cmd(
            helper,
            ["pr-add-issue-comment", "42", "--body", "[codex] acknowledged"],
            env: env,
            stderr_to_stdout: true
          )

        assert Jason.decode!(list_output) |> List.first() |> Map.fetch!("id") == 55
        assert Jason.decode!(create_output)["id"] == 56

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider github pr-issue-comments 42"
        assert log =~ "repo-provider --provider github pr-add-issue-comment 42 --body [codex] acknowledged"
      end
    )
  end

  test "bundled helper routes GitHub run-list and run-view through symphony" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      case "$*" in
        *"run-list"*) printf '24870399231\\n' ;;
        *"run-view"*) printf 'Run 24870399231: success\\n' ;;
        *) printf 'unexpected command\\n' >&2; exit 87 ;;
      esac
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        env = [
          {"PATH", path_with_bin(root)},
          {"SYMPHONY_REPO_PROVIDER_REPOSITORY", "acme/widgets"}
        ]

        {run_list_output, 0} =
          System.cmd(helper, ["run-list", "--branch", "trunk", "--json", "id", "-q", ".[0].id"],
            env: env,
            stderr_to_stdout: true
          )

        {run_view_output, 0} =
          System.cmd(helper, ["run-view", "24870399231", "--log"], env: env, stderr_to_stdout: true)

        assert run_list_output == "24870399231\n"
        assert run_view_output == "Run 24870399231: success\n"

        log = File.read!(log_path)
        assert log =~ "repo-provider --provider github run-list --branch trunk --json id -q .[0].id"
        assert log =~ "repo-provider --provider github run-view 24870399231 --log"
      end
    )
  end

  defp copy_helper!(root) do
    {:ok, bundled_dir} = AutomationPack.bundled_source_dir()
    source = Path.join([bundled_dir, "bin", "repo-provider"])
    destination = Path.join(root, "repo-provider")
    File.cp!(source, destination)
    File.chmod!(destination, 0o755)
    destination
  end

  defp with_fake_symphony(contents, fun) when is_binary(contents) and is_function(fun, 2) do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-provider-helper-test-#{unique}")
    bin_dir = Path.join(root, "bin")
    log_path = Path.join(root, "symphony.log")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(bin_dir)
      File.write!(log_path, "")
      write_executable!(Path.join(bin_dir, "symphony"), contents)
      with_env(%{"SYMPHONY_LOG" => log_path}, fn -> fun.(root, log_path) end)
    after
      File.rm_rf!(root)
    end
  end

  defp path_with_bin(root) do
    Enum.join([Path.join(root, "bin"), System.get_env("PATH") || ""], ":")
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
