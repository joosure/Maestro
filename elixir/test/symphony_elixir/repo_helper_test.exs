defmodule SymphonyElixir.RepoHelperTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.TestSupport.Snapshot
  alias SymphonyElixir.Workspace.AutomationPack

  test "bundled helper routes repo commands through symphony with workspace repo default" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf 'dirty\\n'
      """,
      fn root, log_path ->
        File.mkdir_p!(Path.join(root, "repo"))
        helper = copy_helper!(root)

        assert {"dirty\n", 0} =
                 System.cmd(helper, ["status"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert File.read!(log_path) == "repo status --path repo\n"
      end
    )
  end

  test "bundled helper honors explicit path arguments and remote env" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf 'https://example.test/acme/widgets.git\\n'
      """,
      fn root, log_path ->
        helper = copy_helper!(root)

        assert {"https://example.test/acme/widgets.git\n", 0} =
                 System.cmd(helper, ["remote-url", "--path", "custom-repo"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_PATH", "env-repo"},
                     {"SYMPHONY_REPO_REMOTE", "upstream"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"https://example.test/acme/widgets.git\n", 0} =
                 System.cmd(helper, ["published-head-sha", "feature/repo-helper", "--path", "custom-repo"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_PATH", "env-repo"},
                     {"SYMPHONY_REPO_REMOTE", "upstream"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"https://example.test/acme/widgets.git\n", 0} =
                 System.cmd(helper, ["working-branch", "MT-123"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_BRANCH_WORK_PREFIX", "ticket/work"}
                   ],
                   stderr_to_stdout: true
                 )

        assert File.read!(log_path) ==
                 "repo remote-url --path custom-repo --remote upstream\n" <>
                   "repo published-head-sha feature/repo-helper --path custom-repo --remote upstream\n" <>
                   "repo working-branch MT-123 --work-prefix ticket/work\n"
      end
    )
  end

  test "bundled helper routes write commands with the right repo context" do
    with_fake_symphony(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
      printf 'ok\\n'
      """,
      fn root, log_path ->
        File.mkdir_p!(Path.join(root, "repo"))
        helper = copy_helper!(root)

        assert {"ok\n", 0} =
                 System.cmd(helper, ["preflight"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_REMOTE", "upstream"},
                     {"SYMPHONY_REPO_REMOTE_URL", "https://example.test/acme/widgets.git"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["fetch"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_REMOTE", "upstream"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["diff", "--merge", ":1:README.md", ":2:README.md"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["diff-check"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["enable-rerere"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["clone", "https://example.test/acme/widgets.git", "repo"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["merge", "origin/main"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["sync-base"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_REMOTE", "upstream"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["create-working-branch", "MT-123"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_REMOTE", "upstream"},
                     {"SYMPHONY_REPO_BRANCH_WORK_PREFIX", "ticket/work"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["delete-remote-branch", "feature/repo-helper"],
                   cd: root,
                   env: [
                     {"PATH", path_with_bin(root)},
                     {"SYMPHONY_REPO_REMOTE", "upstream"}
                   ],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["stage-all"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert {"ok\n", 0} =
                 System.cmd(helper, ["commit-staged", "--message", "Add staged file"],
                   cd: root,
                   env: [{"PATH", path_with_bin(root)}],
                   stderr_to_stdout: true
                 )

        assert File.read!(log_path) ==
                 "repo preflight --path repo --remote upstream --remote-url https://example.test/acme/widgets.git\n" <>
                   "repo fetch --path repo --remote upstream\n" <>
                   "repo diff --merge :1:README.md :2:README.md --path repo\n" <>
                   "repo diff-check --path repo\n" <>
                   "repo enable-rerere --path repo\n" <>
                   "repo clone https://example.test/acme/widgets.git repo\n" <>
                   "repo merge origin/main --path repo\n" <>
                   "repo sync-base --path repo --remote upstream\n" <>
                   "repo create-working-branch MT-123 --path repo --remote upstream --work-prefix ticket/work\n" <>
                   "repo delete-remote-branch feature/repo-helper --path repo --remote upstream\n" <>
                   "repo stage-all --path repo\n" <>
                   "repo commit-staged --message Add staged file --path repo\n"
      end
    )
  end

  test "bundled helper preserves the top-level usage contract" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-helper-usage-test-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      assert {output, 64} =
               System.cmd(helper, [],
                 cd: root,
                 env: [{"PATH", System.get_env("PATH") || ""}],
                 stderr_to_stdout: true
               )

      Snapshot.assert_snapshot!("repo_contract/top_level_usage.output.txt", output)
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper rejects unknown commands explicitly" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-helper-unsupported-command-#{unique}")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      assert {output, 64} =
               System.cmd(helper, ["pr-view"],
                 cd: root,
                 env: [{"PATH", System.get_env("PATH") || ""}],
                 stderr_to_stdout: true
               )

      assert output =~ "Unsupported repo command: pr-view"
      assert output =~ "Usage:"
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper fails fast with a clear message when symphony is unavailable" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-helper-missing-symphony-#{unique}")
    bash = System.find_executable("bash")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      helper = copy_helper!(root)

      assert {output, 64} =
               System.cmd(bash, [helper, "status"],
                 cd: root,
                 env: [{"PATH", ""}],
                 stderr_to_stdout: true
               )

      assert output =~ "repo helper requires executable SYMPHONY_CLI or symphony in PATH"
    after
      File.rm_rf!(root)
    end
  end

  test "bundled helper honors SYMPHONY_CLI when symphony is not in PATH" do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-helper-symphony-cli-#{unique}")
    log_path = Path.join(root, "symphony.log")
    bash = System.find_executable("bash")

    try do
      File.rm_rf!(root)
      File.mkdir_p!(root)
      File.mkdir_p!(Path.join(root, "repo"))
      File.write!(log_path, "")
      helper = copy_helper!(root)

      symphony_cli = Path.join(root, "symphony-cli")

      write_executable!(
        symphony_cli,
        """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$SYMPHONY_LOG"
        printf 'clean\\n'
        """
      )

      assert {"clean\n", 0} =
               System.cmd(bash, [helper, "status"],
                 cd: root,
                 env: [
                   {"PATH", ""},
                   {"SYMPHONY_CLI", symphony_cli},
                   {"SYMPHONY_LOG", log_path}
                 ],
                 stderr_to_stdout: true
               )

      assert File.read!(log_path) == "repo status --path repo\n"
    after
      File.rm_rf!(root)
    end
  end

  defp copy_helper!(root) do
    {:ok, bundled_dir} = AutomationPack.bundled_source_dir()
    source = Path.join([bundled_dir, "bin", "repo"])
    destination = Path.join(root, "repo-helper")
    File.cp!(source, destination)
    File.chmod!(destination, 0o755)
    destination
  end

  defp with_fake_symphony(contents, fun) when is_binary(contents) and is_function(fun, 2) do
    unique = System.unique_integer([:positive, :monotonic])
    root = Path.join(System.tmp_dir!(), "repo-helper-test-#{unique}")
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
