defmodule SymphonyElixir.RepoTest do
  use ExUnit.Case

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Repo
  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Preflight
  alias SymphonyElixir.Repo.Status

  test "resolves repository root from nested paths" do
    repo = git_repo!()
    expected_root = git!(repo, ["rev-parse", "--show-toplevel"]) |> String.trim()
    nested = Path.join([repo, "nested", "path"])
    File.mkdir_p!(nested)

    assert {:ok, ^expected_root} = Repo.root(nested)
  end

  test "reads branch, head sha, remote url, and clean status" do
    repo = git_repo!()
    write_commit!(repo, "initial")
    git!(repo, ["remote", "add", "origin", "https://github.com/acme/widgets.git"])
    expected_sha = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

    assert {:ok, "main"} = Repo.current_branch(repo)
    assert {:ok, ^expected_sha} = Repo.head_sha(repo)
    assert {:ok, "https://github.com/acme/widgets.git"} = Repo.remote_url(repo)
    assert {:ok, true} = Repo.clean?(repo)

    assert {:ok, %Status{state: :clean, clean?: true, branch: "main", head_sha: ^expected_sha}} =
             Repo.status(repo)
  end

  test "preflight resolves startup repo facts and fails outside git worktrees" do
    repo = git_repo!()
    write_commit!(repo, "initial")
    git!(repo, ["remote", "add", "upstream", "https://github.com/acme/widgets.git"])
    expected_root = git!(repo, ["rev-parse", "--show-toplevel"]) |> String.trim()
    expected_sha = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

    assert {:ok,
            %Preflight{
              path: ^repo,
              root: ^expected_root,
              remote: "upstream",
              remote_url: "https://github.com/acme/widgets.git",
              base_branch: "trunk",
              current_branch: "main",
              head_sha: ^expected_sha
            }} = Repo.preflight(repo, "upstream", base_branch: "trunk")

    missing_path = tmp_dir!("preflight-missing")

    assert {:error, %Error{code: :not_git_repo, operation: :root, exit_code: 64}} =
             Repo.preflight(missing_path)
  end

  test "resolves provider-neutral base branch from config-like maps and structs" do
    assert Repo.base_branch(%{}, command_runner: fn "git", ["symbolic-ref", "refs/remotes/origin/HEAD"] -> {:error, {1, "missing"}} end) == "main"
    assert Repo.base_branch(%{"base_branch" => "trunk"}) == "trunk"
    assert Repo.base_branch(%{base_branch: "develop"}) == "develop"

    assert Repo.base_branch(%{},
             command_runner: fn "git", ["symbolic-ref", "refs/remotes/origin/HEAD"] ->
               {:ok, "refs/remotes/origin/release\n"}
             end
           ) == "release"
  end

  test "base branch reads options and environment before remote defaults" do
    previous = System.get_env("SYMPHONY_REPO_BASE_BRANCH")

    try do
      System.put_env("SYMPHONY_REPO_BASE_BRANCH", "env-main")

      assert Repo.base_branch(%{}, base_branch: "opts-main") == "opts-main"
      assert Repo.base_branch(%{}) == "env-main"
    after
      restore_env("SYMPHONY_REPO_BASE_BRANCH", previous)
    end
  end

  test "derives deterministic provider-neutral working branches" do
    assert {:ok, "symphony/mt-123"} = Repo.working_branch("MT-123")
    assert {:ok, "feature/tapd-42"} = Repo.working_branch("TAPD 42", work_prefix: "feature")
    assert {:ok, "release/work/issue-99"} = Repo.working_branch("Issue #99", work_prefix: "refs/heads/release/work")

    assert {:error, %Error{code: :invalid_invocation, operation: :working_branch, exit_code: 64}} =
             Repo.working_branch("   ")
  end

  test "working branch reads environment prefix when no option is provided" do
    previous = System.get_env("SYMPHONY_REPO_BRANCH_WORK_PREFIX")

    try do
      System.put_env("SYMPHONY_REPO_BRANCH_WORK_PREFIX", "env/work")

      assert {:ok, "env/work/mt-124"} = Repo.working_branch("MT-124")
      assert {:ok, "opts/work/mt-124"} = Repo.working_branch("MT-124", work_prefix: "opts/work")
    after
      restore_env("SYMPHONY_REPO_BRANCH_WORK_PREFIX", previous)
    end
  end

  test "reads remote default branch from symbolic refs" do
    assert {:ok, "main"} =
             Repo.remote_default_branch(".", "origin",
               command_runner: fn "git", ["symbolic-ref", "refs/remotes/origin/HEAD"] ->
                 {:ok, "refs/remotes/origin/main\n"}
               end
             )

    assert {:error, %Error{code: :remote_not_found, operation: :remote_default_branch}} =
             Repo.remote_default_branch(".", "origin",
               command_runner: fn "git", ["symbolic-ref", "refs/remotes/origin/HEAD"] ->
                 {:ok, "refs/remotes/upstream/main\n"}
               end
             )
  end

  test "returns missing status for paths outside a git worktree" do
    path = tmp_dir!("not-a-repo")

    assert {:ok, %Status{state: :missing, missing?: true, error: %Error{code: :not_git_repo}}} =
             Repo.status(path)

    missing_path = Path.join(path, "missing")

    assert {:ok, %Status{state: :missing, missing?: true, error: %Error{code: :not_git_repo}}} =
             Repo.status(missing_path)
  end

  test "maps injected missing git tooling to repo-core errors" do
    assert {:error, %Error{code: :missing_tooling, operation: :current_branch, exit_code: 64}} =
             Repo.current_branch(".", command_runner: fn "git", ["branch", "--show-current"] -> {:error, {:enoent, ""}} end)
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

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-repo-core-#{name}-#{System.unique_integer([:positive])}")
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
