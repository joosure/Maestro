defmodule SymphonyElixir.Workspace.GitExcludeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workspace.GitExclude

  test "ensure_entry/2 appends a repo-local git exclude entry idempotently" do
    workspace = tmp_dir!("repo")
    exclude_path = Path.join([workspace, ".git", "info", "exclude"])

    on_exit(fn -> File.rm_rf(workspace) end)

    File.mkdir_p!(Path.dirname(exclude_path))
    File.write!(exclude_path, "*.tmp\n")

    assert :ok = GitExclude.ensure_entry(workspace, ".symphony/")
    assert :ok = GitExclude.ensure_entry(workspace, ".symphony/")

    assert File.read!(exclude_path) == "*.tmp\n.symphony/\n"
  end

  test "ensure_entry/2 supports worktree gitdir files" do
    root = tmp_dir!("worktree")
    workspace = Path.join(root, "workspace")
    git_dir = Path.join(root, "actual-git")
    exclude_path = Path.join([git_dir, "info", "exclude"])

    on_exit(fn -> File.rm_rf(root) end)

    File.mkdir_p!(workspace)
    File.mkdir_p!(Path.dirname(exclude_path))
    File.write!(Path.join(workspace, ".git"), "gitdir: #{git_dir}\n")

    assert :ok = GitExclude.ensure_entry(workspace, ".opencode/")
    assert File.read!(exclude_path) == ".opencode/\n"
  end

  test "ensure_entry/2 is a no-op outside git workspaces" do
    workspace = tmp_dir!("plain")

    on_exit(fn -> File.rm_rf(workspace) end)

    assert :ok = GitExclude.ensure_entry(workspace, ".symphony/")
    refute File.exists?(Path.join([workspace, ".git", "info", "exclude"]))
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-git-exclude-#{name}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
