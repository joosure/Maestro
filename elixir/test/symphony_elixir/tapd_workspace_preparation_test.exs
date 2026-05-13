defmodule SymphonyElixir.TapdWorkspacePreparationTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Tracker.Tapd.WorkspacePreparation

  @workpad_filename ".symphony-tapd-workpad.md"

  test "ensure_workpad_ignore/3 appends local git exclude entries idempotently" do
    workspace = tmp_repo!("local")
    exclude_path = Path.join([workspace, ".git", "info", "exclude"])

    on_exit(fn -> File.rm_rf(workspace) end)

    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, nil)
    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, nil)
    assert exclude_entries(exclude_path, @workpad_filename) == 1
  end

  test "ensure_workpad_ignore/3 also protects the nested target repo workpad path" do
    workspace = tmp_dir!("nested")
    repo = tmp_repo_at!(Path.join(workspace, "repo"))
    exclude_path = Path.join([repo, ".git", "info", "exclude"])

    on_exit(fn -> File.rm_rf(workspace) end)

    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, nil)
    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, nil)
    assert exclude_entries(exclude_path, @workpad_filename) == 1
  end

  test "ensure_workpad_ignore/3 appends remote git exclude entries idempotently" do
    workspace = tmp_repo!("remote")
    exclude_path = Path.join([workspace, ".git", "info", "exclude"])

    on_exit(fn -> File.rm_rf(workspace) end)

    remote_runner = fn script ->
      {output, status} = CommandEnv.system_cmd("sh", ["-c", script], stderr_to_stdout: true)
      {:ok, {output, status}}
    end

    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, "worker-1", remote_runner: remote_runner)
    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, "worker-1", remote_runner: remote_runner)
    assert exclude_entries(exclude_path, @workpad_filename) == 1
  end

  test "ensure_workpad_ignore/3 also protects nested target repos remotely" do
    workspace = tmp_dir!("remote-nested")
    repo = tmp_repo_at!(Path.join(workspace, "repo"))
    exclude_path = Path.join([repo, ".git", "info", "exclude"])

    on_exit(fn -> File.rm_rf(workspace) end)

    remote_runner = fn script ->
      {output, status} = CommandEnv.system_cmd("sh", ["-c", script], stderr_to_stdout: true)
      {:ok, {output, status}}
    end

    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, "worker-1", remote_runner: remote_runner)
    assert :ok = WorkspacePreparation.ensure_workpad_ignore(workspace, "worker-1", remote_runner: remote_runner)
    assert exclude_entries(exclude_path, @workpad_filename) == 1
  end

  defp exclude_entries(exclude_path, entry) do
    exclude_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.count(&(&1 == entry))
  end

  defp tmp_repo!(name) do
    name
    |> tmp_path()
    |> tmp_repo_at!()
  end

  defp tmp_repo_at!(path) when is_binary(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)

    {_, 0} = CommandEnv.system_cmd("git", ["-C", path, "init", "-b", "main"], stderr_to_stdout: true)

    path
  end

  defp tmp_dir!(name) do
    path = tmp_path(name)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp tmp_path(name) do
    Path.join(System.tmp_dir!(), "symphony-tapd-workspace-preparation-#{name}-#{System.unique_integer([:positive])}")
  end
end
