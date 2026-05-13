defmodule SymphonyElixir.Repo.GitTest do
  use ExUnit.Case

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Repo
  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Status

  test "classifies uncommitted changes as dirty" do
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")
    File.write!(Path.join(repo, "scratch.txt"), "scratch\n")

    assert {:ok, %Status{state: :dirty, dirty?: true, clean?: false, entries: entries}} =
             Repo.status(repo)

    assert Enum.any?(entries, &match?(%{status: "??", path: "scratch.txt"}, &1))
  end

  test "classifies merge conflicts as conflicted" do
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")

    git!(repo, ["checkout", "-b", "feature/conflict"])
    write_commit!(repo, "feature change", "feature\n")

    git!(repo, ["checkout", "main"])
    write_commit!(repo, "main change", "main\n")

    assert {:error, %Error{code: :conflict, operation: :merge}} =
             Repo.merge(repo, "feature/conflict")

    assert {:ok, %Status{state: :conflicted, conflicted?: true, dirty?: true, entries: entries}} =
             Repo.status(repo)

    assert Enum.any?(entries, &(&1.status in ["UU", "AA", "DD", "AU", "UD", "UA", "DU"]))

    assert {:error, %Error{code: :conflict, operation: :commit_all}} =
             Repo.commit_all(repo, "should not commit conflicts")
  end

  test "classifies detached HEAD and current_branch reports it explicitly" do
    repo = git_repo!()
    write_commit!(repo, "initial")
    sha = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    git!(repo, ["checkout", "--detach", sha])

    assert {:error, %Error{code: :detached_head, operation: :current_branch}} =
             Repo.current_branch(repo)

    assert {:ok, %Status{state: :detached, detached?: true, branch: nil, head_sha: ^sha}} =
             Repo.status(repo)
  end

  test "reports missing remotes separately from generic git failures" do
    repo = git_repo!()

    assert {:error, %Error{code: :remote_not_found, operation: :remote_url, exit_code: 64}} =
             Repo.remote_url(repo, "origin")
  end

  test "creates and switches branches through repo-core" do
    repo = git_repo!()
    write_commit!(repo, "initial")

    assert {:ok, "feature/repo-core"} =
             Repo.create_branch(repo, "feature/repo-core", "HEAD")

    write_commit!(repo, "feature change", "feature\n")

    assert {:ok, "feature/repo-core"} = Repo.current_branch(repo)
    assert {:ok, "main"} = Repo.switch_branch(repo, "main")
    assert {:ok, "main"} = Repo.current_branch(repo)
    assert {:ok, _output} = Repo.merge(repo, "feature/repo-core")
    assert git!(repo, ["log", "-1", "--format=%s"]) |> String.trim() == "feature change"

    assert {:error, %Error{code: :branch_exists, operation: :create_branch}} =
             Repo.create_branch(repo, "feature/repo-core", "HEAD")

    assert {:error, %Error{code: :branch_not_found, operation: :switch_branch}} =
             Repo.switch_branch(repo, "feature/missing")
  end

  test "creates derived working branches through repo-core" do
    repo = git_repo!()
    write_commit!(repo, "initial")

    assert {:ok, "ticket/mt-123"} =
             Repo.create_working_branch(repo, "MT-123", "HEAD", work_prefix: "ticket")

    assert {:ok, "ticket/mt-123"} = Repo.current_branch(repo)
  end

  test "commits dirty worktrees and no-ops clean worktrees" do
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")

    assert {:ok, :noop} = Repo.commit_all(repo, "nothing to commit")

    File.write!(Path.join(repo, "feature.txt"), "feature\n")

    assert {:ok, sha} = Repo.commit_all(repo, "add feature")
    assert String.length(sha) == 40
    assert git!(repo, ["log", "-1", "--format=%s"]) |> String.trim() == "add feature"
    assert {:ok, true} = Repo.clean?(repo)
  end

  test "stages and commits staged changes through repo-core" do
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")
    File.write!(Path.join(repo, "staged.txt"), "staged\n")

    assert {:ok, "staged"} = Repo.stage_all(repo)
    assert git!(repo, ["diff", "--cached", "--name-only"]) |> String.trim() == "staged.txt"

    assert {:ok, sha} = Repo.commit_staged(repo, "add staged file")
    assert String.length(sha) == 40
    assert git!(repo, ["log", "-1", "--format=%s"]) |> String.trim() == "add staged file"
    assert {:ok, true} = Repo.clean?(repo)
  end

  test "pushes and fetches branches against a bare remote" do
    remote = bare_repo!()
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")
    git!(repo, ["remote", "add", "origin", remote])

    assert {:ok, _output} = Repo.push(repo, "origin", "main")
    assert git!(remote, ["show-ref", "--verify", "refs/heads/main"]) =~ "refs/heads/main"

    clone = clone_repo!(remote)
    write_commit!(repo, "second", "second\n")
    assert {:ok, _output} = Repo.push(repo, "origin", "main")

    assert {:ok, _output} = Repo.fetch(clone, "origin")
    published_sha = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()
    assert git!(clone, ["rev-parse", "origin/main"]) |> String.trim() == published_sha
    assert {:ok, ^published_sha} = Repo.published_head_sha(repo, "origin", "main")
  end

  test "clones a branch through repo-core" do
    remote = bare_repo!()
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")
    git!(repo, ["remote", "add", "origin", remote])
    assert {:ok, _output} = Repo.push(repo, "origin", "main")

    clone = tmp_dir!("repo-clone")
    File.rm_rf!(clone)

    assert {:ok, _output} = Repo.clone(remote, clone, "main", depth: 1)
    assert {:ok, "main"} = Repo.current_branch(clone)
  end

  test "deletes remote branches through repo-core" do
    remote = bare_repo!()
    repo = git_repo!()
    write_commit!(repo, "initial", "initial\n")
    git!(repo, ["remote", "add", "origin", remote])
    assert {:ok, "feature/delete-me"} = Repo.create_branch(repo, "feature/delete-me", "HEAD")
    assert {:ok, _output} = Repo.push(repo, "origin", "feature/delete-me")

    assert {:ok, _output} = Repo.delete_remote_branch(repo, "origin", "feature/delete-me")

    assert {_output, status} =
             CommandEnv.system_cmd("git", ["-C", remote, "show-ref", "--verify", "refs/heads/feature/delete-me"], stderr_to_stdout: true)

    assert status != 0
  end

  test "resolves remote default branch from a URL-style lookup" do
    assert {:ok, "trunk"} =
             Repo.remote_default_branch_from_url("https://example.test/acme/widgets.git",
               command_runner: fn "git", ["ls-remote", "--symref", "https://example.test/acme/widgets.git", "HEAD"] ->
                 {:ok, "ref: refs/heads/trunk\tHEAD\nabc\tHEAD\n"}
               end
             )

    assert {:error, %Error{code: :remote_default_branch_unavailable, operation: :remote_default_branch_from_url}} =
             Repo.remote_default_branch_from_url("https://example.test/acme/widgets.git",
               command_runner: fn "git", ["ls-remote", "--symref", "https://example.test/acme/widgets.git", "HEAD"] ->
                 {:ok, "abc\tHEAD\n"}
               end
             )
  end

  test "classifies rejected pushes" do
    assert {:error, %Error{code: :push_rejected, operation: :push}} =
             Repo.push(".", "origin", "main",
               command_runner: fn "git", ["push", "origin", "main"] ->
                 {:error, {1, "! [rejected] main -> main (non-fast-forward)\n"}}
               end
             )
  end

  test "classifies remote auth failures" do
    assert {:error, %Error{code: :auth_failed, operation: :fetch}} =
             Repo.fetch(".", "origin",
               command_runner: fn "git", ["fetch", "origin"] ->
                 {:error, {128, "fatal: Authentication failed for 'https://example.test/acme/widgets.git/'\n"}}
               end
             )

    assert {:error, %Error{code: :auth_failed, operation: :push}} =
             Repo.push(".", "origin", "main",
               command_runner: fn "git", ["push", "origin", "main"] ->
                 {:error, {128, "git@example.test: Permission denied (publickey).\nfatal: Could not read from remote repository.\n"}}
               end
             )
  end

  test "classifies unavailable remotes" do
    target = Path.join(tmp_dir!("clone-parent"), "repo")

    assert {:error, %Error{code: :remote_unavailable, operation: :clone, retryable?: true}} =
             Repo.clone("https://example.test/acme/widgets.git", target,
               command_runner: fn "git", ["clone", "https://example.test/acme/widgets.git", ^target] ->
                 {:error, {128, "fatal: unable to access 'https://example.test/acme/widgets.git/': Could not resolve host: example.test\n"}}
               end
             )

    assert {:error, %Error{code: :remote_unavailable, operation: :published_head_sha, retryable?: true}} =
             Repo.published_head_sha(".", "origin", "main",
               command_runner: fn "git", ["ls-remote", "origin", "refs/heads/main"] ->
                 {:error, {128, "ssh: Could not resolve hostname example.test: nodename nor servname provided\nfatal: Could not read from remote repository.\n"}}
               end
             )
  end

  test "classifies ff-only merge divergence" do
    assert {:error, %Error{code: :branch_diverged, operation: :merge}} =
             Repo.merge(".", "origin/main",
               ff_only: true,
               command_runner: fn "git", ["merge", "--ff-only", "origin/main"] ->
                 {:error, {128, "fatal: Not possible to fast-forward, aborting.\n"}}
               end
             )
  end

  test "syncs base branch through fetch and merge" do
    repo = tmp_dir!("sync-base")

    runner = fn
      "git", ["-C", ^repo, "fetch", "upstream"] ->
        {:ok, "fetched\n"}

      "git", ["-C", ^repo, "merge", "--ff-only", "upstream/trunk"] ->
        {:ok, "Fast-forward\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:ok, "fetched\nFast-forward"} =
             Repo.sync_base(repo, "upstream", "trunk", ff_only: true, command_runner: runner)
  end

  test "reads diffs and validates diff whitespace through repo-core" do
    repo = tmp_dir!("diff")

    runner = fn
      "git", ["-C", ^repo, "diff"] ->
        {:ok, "diff --git a/README.md b/README.md\n"}

      "git", ["-C", ^repo, "diff", "--merge", ":1:README.md", ":2:README.md"] ->
        {:ok, "combined diff\n"}

      "git", ["-C", ^repo, "diff", "--check"] ->
        {:ok, ""}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:ok, "diff --git a/README.md b/README.md"} =
             Repo.diff(repo, [], command_runner: runner)

    assert {:ok, "combined diff"} =
             Repo.diff(repo, ["--merge", ":1:README.md", ":2:README.md"], command_runner: runner)

    assert {:ok, "ok"} = Repo.diff_check(repo, command_runner: runner)
  end

  test "enables rerere through repo-core config commands" do
    repo = tmp_dir!("enable-rerere")

    runner = fn
      "git", ["-C", ^repo, "config", "--local", "rerere.enabled", "true"] ->
        {:ok, ""}

      "git", ["-C", ^repo, "config", "--local", "rerere.autoupdate", "true"] ->
        {:ok, ""}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert {:ok, "rerere enabled"} = Repo.enable_rerere(repo, command_runner: runner)
  end

  test "classifies missing published heads" do
    assert {:error, %Error{code: :branch_not_found, operation: :published_head_sha}} =
             Repo.published_head_sha(".", "origin", "missing",
               command_runner: fn "git", ["ls-remote", "origin", "refs/heads/missing"] ->
                 {:ok, ""}
               end
             )
  end

  defp git_repo! do
    repo = tmp_dir!("repo")
    git!(repo, ["init", "--initial-branch=main"])
    git!(repo, ["config", "user.name", "Test User"])
    git!(repo, ["config", "user.email", "test@example.com"])
    repo
  end

  defp write_commit!(repo, message, content \\ "hello\n") do
    File.write!(Path.join(repo, "README.md"), content)
    git!(repo, ["add", "README.md"])
    git!(repo, ["commit", "-m", message])
  end

  defp bare_repo! do
    repo = tmp_dir!("remote.git")
    git!(repo, ["init", "--bare", "--initial-branch=main"])
    repo
  end

  defp clone_repo!(remote) do
    path = tmp_dir!("clone")
    File.rm_rf!(path)
    git_global!(["clone", remote, path])
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-repo-core-git-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp git!(repo, args) do
    case CommandEnv.system_cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end

  defp git_global!(args) do
    case CommandEnv.system_cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end
end
