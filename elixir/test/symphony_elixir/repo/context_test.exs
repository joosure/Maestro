defmodule SymphonyElixir.Repo.ContextTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Repo.Context

  test "defaults to current directory and origin remote" do
    assert %Context{
             path: ".",
             remote: "origin",
             remote_url: nil,
             base_branch: nil,
             work_prefix: nil
           } = Context.new(%{})
  end

  test "normalizes repo config from atom and string keyed maps" do
    assert %Context{
             path: "repo",
             remote: "upstream",
             remote_url: "https://example.test/acme/widgets.git",
             base_branch: "main",
             work_prefix: "feature"
           } =
             Context.new(%{
               path: "repo",
               base_branch: "main",
               branch: %{"work_prefix" => "feature"},
               remote: %{"name" => "upstream", "url" => "https://example.test/acme/widgets.git"}
             })
  end

  test "explicit opts override repo config" do
    assert %Context{
             path: "override-repo",
             remote: "fork",
             remote_url: "https://example.test/acme/fork.git",
             base_branch: "release",
             work_prefix: "hotfix"
           } =
             Context.new(
               %{
                 path: "repo",
                 base_branch: "main",
                 branch: %{work_prefix: "feature"},
                 remote: %{name: "origin", url: "https://example.test/acme/widgets.git"}
               },
               path: "override-repo",
               remote: "fork",
               remote_url: "https://example.test/acme/fork.git",
               base_branch: "release",
               work_prefix: "hotfix"
             )
  end

  test "repo opts preserve command injection while applying context path and remote" do
    runner = fn _command, _args -> {:ok, ""} end

    opts =
      Context.repo_opts(
        %{
          path: "repo",
          base_branch: "main",
          branch: %{work_prefix: "feature"},
          remote: %{name: "upstream", url: "https://example.test/acme/widgets.git"}
        },
        command_runner: runner
      )

    assert Keyword.get(opts, :command_runner) == runner
    assert Keyword.get(opts, :path) == "repo"
    assert Keyword.get(opts, :remote) == "upstream"
    assert Keyword.get(opts, :remote_url) == "https://example.test/acme/widgets.git"
    assert Keyword.get(opts, :base_branch) == "main"
    assert Keyword.get(opts, :work_prefix) == "feature"
  end

  test "working branch uses configured branch prefix" do
    assert {:ok, "ticket/mt-123"} =
             Context.working_branch(%{branch: %{work_prefix: "ticket"}}, "MT-123")
  end

  test "base branch lookup uses configured repo path and remote" do
    repo_path = tmp_dir!("context-base-branch")

    runner = fn
      "git", ["-C", ^repo_path, "symbolic-ref", "refs/remotes/upstream/HEAD"] ->
        {:ok, "refs/remotes/upstream/trunk\n"}

      command, args ->
        flunk("unexpected command: #{inspect({command, args})}")
    end

    assert Context.base_branch(%{path: repo_path, remote: %{name: "upstream"}}, command_runner: runner) == "trunk"
  end

  defp tmp_dir!(name) do
    path = Path.join(System.tmp_dir!(), "symphony-repo-context-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end
end
