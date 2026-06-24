defmodule SymphonyElixir.RepoDynamicToolTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Inventory

  @sensitive_env ~w[
    CNB_TOKEN
    GH_TOKEN
    GITHUB_TOKEN
    LINEAR_API_KEY
    OPENAI_API_KEY
    OPENROUTER_API_KEY
    SYMPHONY_LINEAR_API_KEY
    TAPD_API_PASSWORD
    TAPD_API_USER
  ]

  test "repo-core typed tools advertise production metadata and resolve inventory capabilities" do
    context = repo_tool_context(repo_config(System.tmp_dir!()))
    tool_specs = DynamicTool.Context.tool_specs(context)
    tool_metadata = DynamicTool.Context.tool_metadata(context)
    names = Enum.map(tool_specs, &Map.fetch!(&1, "name"))

    assert Enum.sort(names) ==
             Enum.sort([
               "repo_checkout",
               "repo_diff",
               "repo_commit",
               "repo_push"
             ])

    assert tool_metadata["repo_checkout"]["capability"] == "repo.checkout"
    assert tool_metadata["repo_checkout"]["sourceKind"] == "repo"
    assert tool_metadata["repo_checkout"]["sideEffect"] == "write"
    assert tool_metadata["repo_diff"]["sideEffect"] == "read_only"

    assert tool_specs
           |> Enum.find(&(&1["name"] == "repo_commit"))
           |> get_in(["inputSchema", "properties", "mode", "enum"]) == ["all", "staged", nil]

    assert {:ok, resolved} =
             Inventory.resolve_required(context, [
               "repo.checkout",
               "repo.diff",
               "repo.commit",
               "repo.push"
             ])

    assert Enum.map(resolved, & &1.tool) == [
             "repo_checkout",
             "repo_diff",
             "repo_commit",
             "repo_push"
           ]
  end

  test "repo-core typed tools can checkout, diff, commit, and push through repo facade" do
    %{repo_path: repo_path, remote_path: remote_path} = setup_git_repo!()
    context = repo_tool_context(repo_config(repo_path))

    assert {:success,
            %{
              "data" => %{
                "action" => "created",
                "branch" => "typed/demo-42",
                "status" => %{"clean" => true}
              }
            }} =
             DynamicTool.execute(context, "repo_checkout", %{"identifier" => "DEMO-42"})

    File.write!(Path.join(repo_path, "README.md"), "# Repo Tool Test\n\nrepo typed tool validation\n")

    assert {:success,
            %{
              "data" => %{
                "diff" => diff,
                "diffCheck" => "ok"
              }
            }} =
             DynamicTool.execute(context, "repo_diff", %{"check" => true})

    assert diff =~ "repo typed tool validation"

    assert {:success,
            %{
              "data" => %{
                "action" => "committed",
                "headSha" => head_sha,
                "status" => %{"clean" => true}
              }
            }} =
             DynamicTool.execute(context, "repo_commit", %{"message" => "Add typed repo tool validation"})

    assert is_binary(head_sha)

    assert {:success,
            %{
              "data" => %{
                "branch" => "typed/demo-42",
                "remote" => "origin",
                "headSha" => ^head_sha,
                "publishedHeadSha" => ^head_sha
              }
            }} =
             DynamicTool.execute(context, "repo_push", %{"set_upstream" => true})

    assert {published, 0} =
             System.cmd(
               "git",
               ["--git-dir", remote_path, "rev-parse", "refs/heads/typed/demo-42"],
               command_opts()
             )

    assert String.trim(published) == head_sha
  end

  test "repo commit keeps canonical schema but normalizes common stage-all aliases" do
    %{repo_path: repo_path} = setup_git_repo!()
    context = repo_tool_context(repo_config(repo_path))

    File.write!(Path.join(repo_path, "STATUS.txt"), "feedback_round=typed-tool-alias\n")

    assert {:success,
            %{
              "data" => %{
                "action" => "committed",
                "headSha" => head_sha,
                "status" => %{"clean" => true}
              },
              "warnings" => [warning]
            }} =
             DynamicTool.execute(context, "repo_commit", %{
               "message" => "Normalize stage-all alias",
               "mode" => "stage_all"
             })

    assert is_binary(head_sha)
    assert warning =~ "canonical mode \"all\""
  end

  test "repo diff normalizes JSON-encoded args arrays from typed tool callers" do
    %{repo_path: repo_path} = setup_git_repo!()
    context = repo_tool_context(repo_config(repo_path))

    File.write!(Path.join(repo_path, "README.md"), "# Repo Tool Test\n\njson encoded diff args\n")

    assert {:success,
            %{
              "data" => %{
                "diff" => diff,
                "diffCheck" => "ok"
              }
            }} =
             DynamicTool.execute(context, "repo_diff", %{
               "args" => Jason.encode!(["master"]),
               "check" => true
             })

    assert diff =~ "json encoded diff args"
  end

  test "repo-core typed tools resolve relative repo path from dynamic bridge workspace context" do
    workspace_root = Path.expand(SymphonyElixir.Config.settings!().workspace.root)
    File.mkdir_p!(workspace_root)

    %{root: root, repo_path: repo_path} = setup_git_repo!(workspace_root)
    context = repo_tool_context(repo_config("repo"))

    assert File.dir?(Path.join(repo_path, ".git"))

    assert {:success,
            %{
              "data" => %{
                "action" => "created",
                "branch" => "typed/demo-43",
                "status" => %{"clean" => true}
              }
            }} =
             DynamicTool.execute(context, "repo_checkout", %{"identifier" => "DEMO-43"}, workspace: root)

    assert File.dir?(Path.join(repo_path, ".git"))
  end

  test "repo-core typed tools fail fast when relative repo path lacks workspace context" do
    context = repo_tool_context(repo_config("repo"))

    assert {:failure,
            %{
              "error" => %{
                "code" => "repo_dynamic_tool_workspace_required",
                "message" => "Repo dynamic tool requires workspace context to resolve relative repo path \"repo\".",
                "details" => %{"repo_path" => "repo", "source_kind" => "repo"}
              }
            }} =
             DynamicTool.execute(context, "repo_checkout", %{"identifier" => "DEMO-44"})
  end

  test "repo-core typed tools return structured validation failures" do
    context = repo_tool_context(repo_config(System.tmp_dir!()))

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Repo checkout requires either branch or identifier."
              }
            }} =
             DynamicTool.execute(context, "repo_checkout", %{})

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_arguments",
                "message" => "Missing required string field message."
              }
            }} =
             DynamicTool.execute(context, "repo_commit", %{})
  end

  defp repo_tool_context(repo) do
    DynamicTool.capture_context(dynamic_tool_sources: [{SymphonyElixir.Repo.DynamicToolSource, repo}])
  end

  defp repo_config(path) do
    %{
      path: path,
      base_branch: "master",
      remote: %{name: "origin"},
      branch: %{work_prefix: "typed"}
    }
  end

  defp setup_git_repo!(root_parent \\ System.tmp_dir!()) do
    root = Path.join(root_parent, "symphony-repo-dynamic-tool-#{System.unique_integer([:positive])}")
    remote_path = Path.join(root, "remote.git")
    repo_path = Path.join(root, "repo")

    File.rm_rf!(root)
    File.mkdir_p!(root)

    run!("git", ["init", "--bare", remote_path])
    run!("git", ["clone", remote_path, repo_path])
    run!("git", ["-C", repo_path, "config", "user.email", "repo-tool@example.invalid"])
    run!("git", ["-C", repo_path, "config", "user.name", "Repo Tool Test"])

    File.write!(Path.join(repo_path, "README.md"), "# Repo Tool Test\n")
    run!("git", ["-C", repo_path, "add", "README.md"])
    run!("git", ["-C", repo_path, "commit", "-m", "Initial commit"])
    run!("git", ["-C", repo_path, "push", "-u", "origin", "master"])

    on_exit(fn -> File.rm_rf(root) end)

    %{root: root, repo_path: repo_path, remote_path: remote_path}
  end

  defp run!(command, args) do
    case System.cmd(command, args, command_opts()) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("expected #{command} #{Enum.join(args, " ")} to succeed, got status #{status}: #{output}")
    end
  end

  defp command_opts do
    [stderr_to_stdout: true, env: Enum.map(@sensitive_env, &{&1, nil})]
  end
end
