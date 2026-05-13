defmodule SymphonyElixir.RepoCLITest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.CLI.Repo, as: RepoCLI

  test "renders help without touching git" do
    assert {stdout, "", 0} = RepoCLI.evaluate(["--help"], cli_deps())
    assert stdout =~ "Usage: symphony repo <command>"
    assert stdout =~ "current-branch"
    assert stdout =~ "status"
    assert stdout =~ "clone <remote-url> <target-path>"
    assert stdout =~ "published-head-sha <branch>"
    assert stdout =~ "working-branch <identifier>"
    assert stdout =~ "preflight"
    assert stdout =~ "diff [--merge]"
    assert stdout =~ "diff-check [<ref-or-path> ...]"
    assert stdout =~ "merge <ref>"
    assert stdout =~ "sync-base"
    assert stdout =~ "enable-rerere"
    assert stdout =~ "delete-remote-branch <branch>"
    assert stdout =~ "create-working-branch <identifier>"
    assert stdout =~ "stage-all"
    assert stdout =~ "commit-all --message <message>"
    assert stdout =~ "commit-staged --message <message>"
  end

  test "rejects unknown commands with usage" do
    assert {"", stderr, 64} = RepoCLI.evaluate(["wat"], cli_deps())
    assert stderr =~ "Unknown repo command: wat"
    assert stderr =~ "Usage: symphony repo <command>"
  end

  test "root honors --path and renders a scalar result" do
    repo_root = tmp_dir!("root")
    expected = repo_root <> "\n"

    runner = fn
      "git", ["-C", ^repo_root, "rev-parse", "--show-toplevel"] ->
        {:ok, repo_root <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {^expected, "", 0} = RepoCLI.evaluate(["root", "--path", repo_root], cli_deps(runner))
  end

  test "current-branch and head-sha render read-only git facts" do
    sha = String.duplicate("a", 40)
    expected_sha = sha <> "\n"

    runner = fn
      "git", ["branch", "--show-current"] ->
        {:ok, "feature/repo-cli\n"}

      "git", ["rev-parse", "HEAD"] ->
        {:ok, sha <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps = cli_deps(runner)

    assert {"feature/repo-cli\n", "", 0} = RepoCLI.evaluate(["current-branch"], deps)
    assert {^expected_sha, "", 0} = RepoCLI.evaluate(["head-sha"], deps)
  end

  test "remote-url honors --remote" do
    runner = fn
      "git", ["remote", "get-url", "upstream"] ->
        {:ok, "https://example.test/acme/widgets.git\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"https://example.test/acme/widgets.git\n", "", 0} =
             RepoCLI.evaluate(["remote-url", "--remote", "upstream"], cli_deps(runner))
  end

  test "published-head-sha honors path and remote context" do
    repo_root = tmp_dir!("published-head")
    sha = String.duplicate("c", 40)

    runner = fn
      "git", ["-C", ^repo_root, "ls-remote", "upstream", "refs/heads/feature/repo-cli"] ->
        {:ok, "#{sha}\trefs/heads/feature/repo-cli\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {stdout, "", 0} =
             RepoCLI.evaluate(
               ["published-head-sha", "feature/repo-cli", "--path", repo_root, "--remote", "upstream"],
               cli_deps(runner)
             )

    assert stdout == sha <> "\n"
  end

  test "uses repo config defaults when CLI path and remote options are omitted" do
    repo_path = tmp_dir!("configured-repo")

    runner = fn
      "git", ["-C", ^repo_path, "remote", "get-url", "upstream"] ->
        {:ok, "https://example.test/configured/widgets.git\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps =
      runner
      |> cli_deps()
      |> Map.put(:repo_config, fn -> %{path: repo_path, remote: %{name: "upstream"}} end)

    assert {"https://example.test/configured/widgets.git\n", "", 0} =
             RepoCLI.evaluate(["remote-url"], deps)
  end

  test "base-branch uses repo-core options and injected git runner" do
    repo_root = tmp_dir!("base-branch")
    parent = self()

    runner = fn
      "git", ["-C", ^repo_root, "symbolic-ref", "refs/remotes/upstream/HEAD"] ->
        send(parent, :looked_up_upstream_head)
        {:ok, "refs/remotes/upstream/trunk\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    without_env("SYMPHONY_REPO_BASE_BRANCH", fn ->
      assert {"trunk\n", "", 0} =
               RepoCLI.evaluate(["base-branch", "--path", repo_root, "--remote", "upstream"], cli_deps(runner))
    end)

    assert_received :looked_up_upstream_head
  end

  test "base-branch uses configured repo base branch without touching git" do
    deps =
      unexpected_command()
      |> cli_deps()
      |> Map.put(:repo_config, fn -> %{base_branch: "release"} end)

    assert {"release\n", "", 0} = RepoCLI.evaluate(["base-branch"], deps)
  end

  test "working-branch derives branch names from CLI or config prefix without touching git" do
    deps =
      unexpected_command()
      |> cli_deps()
      |> Map.put(:repo_config, fn -> %{branch: %{work_prefix: "configured/work"}} end)

    assert {"configured/work/mt-123\n", "", 0} = RepoCLI.evaluate(["working-branch", "MT-123"], deps)
    assert {"cli/work/mt-123\n", "", 0} = RepoCLI.evaluate(["working-branch", "MT-123", "--work-prefix", "cli/work"], deps)
  end

  test "status renders summarized provider-neutral status" do
    repo_root = tmp_dir!("status")
    sha = String.duplicate("b", 40)
    expected = "state=dirty\nroot=#{repo_root}\nbranch=feature/repo-cli\nhead_sha=#{sha}\nentries=2\n"

    runner = fn
      "git", ["rev-parse", "--show-toplevel"] ->
        {:ok, repo_root <> "\n"}

      "git", ["-C", ^repo_root, "status", "--porcelain=v1", "-z", "--untracked-files=all"] ->
        {:ok, " M README.md\0?? scratch.txt\0"}

      "git", ["-C", ^repo_root, "branch", "--show-current"] ->
        {:ok, "feature/repo-cli\n"}

      "git", ["-C", ^repo_root, "rev-parse", "HEAD"] ->
        {:ok, sha <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {^expected, "", 0} =
             RepoCLI.evaluate(["status"], cli_deps(runner))
  end

  test "preflight renders resolved startup repo facts" do
    repo_root = tmp_dir!("preflight")
    sha = String.duplicate("d", 40)

    runner = fn
      "git", ["-C", ^repo_root, "rev-parse", "--show-toplevel"] ->
        {:ok, repo_root <> "\n"}

      "git", ["-C", ^repo_root, "branch", "--show-current"] ->
        {:ok, "feature/repo-cli\n"}

      "git", ["-C", ^repo_root, "rev-parse", "HEAD"] ->
        {:ok, sha <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps =
      runner
      |> cli_deps()
      |> Map.put(:repo_config, fn ->
        %{
          path: repo_root,
          remote: %{name: "upstream", url: "https://example.test/acme/widgets.git"},
          base_branch: "release"
        }
      end)

    expected =
      "state=ready\n" <>
        "path=#{repo_root}\n" <>
        "root=#{repo_root}\n" <>
        "remote=upstream\n" <>
        "remote_url=https://example.test/acme/widgets.git\n" <>
        "base_branch=release\n" <>
        "current_branch=feature/repo-cli\n" <>
        "head_sha=#{sha}\n"

    assert {^expected, "", 0} =
             RepoCLI.evaluate(["preflight"], deps)
  end

  test "diff commands use repo-core diff operations" do
    repo_root = tmp_dir!("diff")

    runner = fn
      "git", ["-C", ^repo_root, "diff"] ->
        {:ok, "diff output\n"}

      "git", ["-C", ^repo_root, "diff", "--cached"] ->
        {:ok, "staged diff\n"}

      "git", ["-C", ^repo_root, "diff", "--merge", ":1:README.md", ":2:README.md"] ->
        {:ok, "merge diff\n"}

      "git", ["-C", ^repo_root, "diff", "--check"] ->
        {:ok, ""}

      "git", ["-C", ^repo_root, "diff", "--check", "origin/main...HEAD"] ->
        {:ok, ""}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps = cli_deps(runner)

    assert {"diff output\n", "", 0} =
             RepoCLI.evaluate(["diff", "--path", repo_root], deps)

    assert {"merge diff\n", "", 0} =
             RepoCLI.evaluate(["diff", "--merge", ":1:README.md", ":2:README.md", "--path", repo_root], deps)

    assert {"staged diff\n", "", 0} =
             RepoCLI.evaluate(["diff", "--staged", "--path", repo_root], deps)

    assert {"ok\n", "", 0} =
             RepoCLI.evaluate(["diff-check", "--path", repo_root], deps)

    assert {"ok\n", "", 0} =
             RepoCLI.evaluate(["diff-check", "origin/main...HEAD", "--path", repo_root], deps)
  end

  test "clone renders write command result and accepts branch and depth" do
    parent_dir = tmp_dir!("clone-parent")
    target_path = Path.join(parent_dir, "repo")

    runner = fn
      "git", ["clone", "--depth", "1", "--branch", "main", "https://example.test/acme/widgets.git", ^target_path] ->
        {:ok, "cloned\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"cloned\n", "", 0} =
             RepoCLI.evaluate(
               ["clone", "https://example.test/acme/widgets.git", target_path, "--branch", "main", "--depth", "1"],
               cli_deps(runner)
             )
  end

  test "fetch and push use configured path and remote context" do
    repo_root = tmp_dir!("write-remote")

    runner = fn
      "git", ["-C", ^repo_root, "fetch", "upstream"] ->
        {:ok, "fetched\n"}

      "git", ["-C", ^repo_root, "push", "-u", "upstream", "feature/repo-cli"] ->
        {:ok, "pushed\n"}

      "git", ["-C", ^repo_root, "push", "--force-with-lease", "upstream", "feature/repo-cli"] ->
        {:ok, "force-pushed\n"}

      "git", ["-C", ^repo_root, "push", "upstream", "--delete", "feature/repo-cli"] ->
        {:ok, "deleted\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps = cli_deps(runner)

    assert {"fetched\n", "", 0} =
             RepoCLI.evaluate(["fetch", "--path", repo_root, "--remote", "upstream"], deps)

    assert {"pushed\n", "", 0} =
             RepoCLI.evaluate(["push", "feature/repo-cli", "--path", repo_root, "--remote", "upstream", "--set-upstream"], deps)

    assert {"force-pushed\n", "", 0} =
             RepoCLI.evaluate(["push", "feature/repo-cli", "--path", repo_root, "--remote", "upstream", "--force-with-lease"], deps)

    assert {"deleted\n", "", 0} =
             RepoCLI.evaluate(["delete-remote-branch", "feature/repo-cli", "--path", repo_root, "--remote", "upstream"], deps)
  end

  test "merge uses repo-core merge operation" do
    repo_root = tmp_dir!("merge")

    runner = fn
      "git", ["-C", ^repo_root, "merge", "origin/main"] ->
        {:ok, "Already up to date.\n"}

      "git", ["-C", ^repo_root, "merge", "--ff-only", "origin/feature"] ->
        {:ok, "Fast-forward\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"Already up to date.\n", "", 0} =
             RepoCLI.evaluate(["merge", "origin/main", "--path", repo_root], cli_deps(runner))

    assert {"Fast-forward\n", "", 0} =
             RepoCLI.evaluate(["merge", "origin/feature", "--path", repo_root, "--ff-only"], cli_deps(runner))
  end

  test "sync-base fetches configured remote and merges configured or explicit base" do
    repo_root = tmp_dir!("sync-base")

    runner = fn
      "git", ["-C", ^repo_root, "fetch", "upstream"] ->
        {:ok, "fetched\n"}

      "git", ["-C", ^repo_root, "merge", "upstream/release"] ->
        {:ok, "Already up to date.\n"}

      "git", ["-C", ^repo_root, "merge", "--ff-only", "upstream/hotfix"] ->
        {:ok, "Fast-forward\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps =
      runner
      |> cli_deps()
      |> Map.put(:repo_config, fn -> %{path: repo_root, base_branch: "release", remote: %{name: "upstream"}} end)

    assert {"fetched\nAlready up to date.\n", "", 0} =
             RepoCLI.evaluate(["sync-base"], deps)

    assert {"fetched\nFast-forward\n", "", 0} =
             RepoCLI.evaluate(["sync-base", "--base", "hotfix", "--ff-only"], deps)
  end

  test "enable-rerere configures rerere through repo-core" do
    repo_root = tmp_dir!("enable-rerere")

    runner = fn
      "git", ["-C", ^repo_root, "config", "--local", "rerere.enabled", "true"] ->
        {:ok, ""}

      "git", ["-C", ^repo_root, "config", "--local", "rerere.autoupdate", "true"] ->
        {:ok, ""}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"rerere enabled\n", "", 0} =
             RepoCLI.evaluate(["enable-rerere", "--path", repo_root], cli_deps(runner))
  end

  test "create and switch branch use repo-core side-effect operations" do
    repo_root = tmp_dir!("branches")

    runner = fn
      "git", ["-C", ^repo_root, "switch", "-c", "feature/repo-cli", "main"] ->
        {:ok, "created\n"}

      "git", ["-C", ^repo_root, "switch", "feature/repo-cli"] ->
        {:ok, "switched\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps = cli_deps(runner)

    assert {"feature/repo-cli\n", "", 0} =
             RepoCLI.evaluate(["create-branch", "feature/repo-cli", "--base", "main", "--path", repo_root], deps)

    assert {"feature/repo-cli\n", "", 0} =
             RepoCLI.evaluate(["switch-branch", "--branch", "feature/repo-cli", "--path", repo_root], deps)
  end

  test "create-working-branch derives branch and defaults base to configured remote branch" do
    repo_root = tmp_dir!("create-working-branch")

    runner = fn
      "git", ["-C", ^repo_root, "switch", "-c", "ticket/mt-123", "upstream/release"] ->
        {:ok, "created\n"}

      "git", ["-C", ^repo_root, "switch", "-c", "hotfix/mt-123", "HEAD"] ->
        {:ok, "created\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps =
      runner
      |> cli_deps()
      |> Map.put(:repo_config, fn ->
        %{path: repo_root, base_branch: "release", remote: %{name: "upstream"}, branch: %{work_prefix: "ticket"}}
      end)

    assert {"ticket/mt-123\n", "", 0} =
             RepoCLI.evaluate(["create-working-branch", "MT-123"], deps)

    assert {"hotfix/mt-123\n", "", 0} =
             RepoCLI.evaluate(["create-working-branch", "MT-123", "--base", "HEAD", "--work-prefix", "hotfix"], deps)
  end

  test "commit-all renders noop when the repo is already clean" do
    repo_root = tmp_dir!("commit-clean")
    sha = String.duplicate("c", 40)

    runner = fn
      "git", ["-C", ^repo_root, "rev-parse", "--show-toplevel"] ->
        {:ok, repo_root <> "\n"}

      "git", ["-C", ^repo_root, "status", "--porcelain=v1", "-z", "--untracked-files=all"] ->
        {:ok, ""}

      "git", ["-C", ^repo_root, "branch", "--show-current"] ->
        {:ok, "feature/repo-cli\n"}

      "git", ["-C", ^repo_root, "rev-parse", "HEAD"] ->
        {:ok, sha <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"noop\n", "", 0} =
             RepoCLI.evaluate(["commit-all", "--path", repo_root, "--message", "Nothing to commit"], cli_deps(runner))
  end

  test "stage-all and commit-staged use repo-core staged commit operations" do
    repo_root = tmp_dir!("staged-commit")
    sha = String.duplicate("e", 40)

    runner = fn
      "git", ["-C", ^repo_root, "add", "-A"] ->
        {:ok, ""}

      "git", ["-C", ^repo_root, "commit", "-m", "Add staged file"] ->
        {:ok, "committed\n"}

      "git", ["-C", ^repo_root, "rev-parse", "HEAD"] ->
        {:ok, sha <> "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    deps = cli_deps(runner)

    assert {"staged\n", "", 0} =
             RepoCLI.evaluate(["stage-all", "--path", repo_root], deps)

    assert {stdout, "", 0} =
             RepoCLI.evaluate(["commit-staged", "--path", repo_root, "--message", "Add staged file"], deps)

    assert stdout == sha <> "\n"
  end

  test "renders repo-core errors to stderr with the repo error exit code" do
    runner = fn
      "git", ["branch", "--show-current"] ->
        {:ok, "\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {"", "Git HEAD is detached\n", 1} = RepoCLI.evaluate(["current-branch"], cli_deps(runner))
  end

  test "main writes output and halts with the evaluated status" do
    parent = self()

    runner = fn
      "git", ["branch", "--show-current"] -> {:ok, "feature/repo-cli\n"}
      command, args -> flunk("unexpected command: #{inspect({command, args})}")
    end

    deps =
      runner
      |> cli_deps()
      |> Map.merge(%{
        stdout: fn output -> send(parent, {:stdout, output}) end,
        stderr: fn output -> send(parent, {:stderr, output}) end,
        halt: fn status -> throw({:halt, status}) end
      })

    assert catch_throw(RepoCLI.main(["current-branch"], deps)) == {:halt, 0}
    assert_received {:stdout, "feature/repo-cli\n"}
    refute_received {:stderr, _output}
  end

  defp cli_deps(command_runner \\ &unexpected_command/2) when is_function(command_runner, 2) do
    %{
      command_opts: fn -> [command_runner: command_runner] end,
      repo_config: fn -> nil end,
      stdout: fn _output -> :ok end,
      stderr: fn _output -> :ok end,
      halt: fn _status -> raise "halt should not be called from evaluate/2" end
    }
  end

  defp unexpected_command(command, args) do
    flunk("unexpected command: #{inspect({command, args})}")
  end

  defp unexpected_command do
    &unexpected_command/2
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-repo-cli-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp without_env(key, fun) do
    previous = System.get_env(key)

    try do
      System.delete_env(key)
      fun.()
    after
      restore_env(key, previous)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
