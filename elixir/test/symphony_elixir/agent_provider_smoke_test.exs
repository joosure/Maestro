defmodule SymphonyElixir.AgentProviderSmokeTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentProvider.{Config, Session, Smoke, TurnResult}
  alias SymphonyElixir.Workflow.Template, as: TemplateRegistry

  setup do
    previous_workflow_path = Application.fetch_env(:symphony_elixir, :workflow_file_path)

    on_exit(fn ->
      restore_workflow_path(previous_workflow_path)
    end)

    :ok
  end

  test "runs first-turn smoke and always cleans up the temporary workspace" do
    parent = self()
    workspace_ref = :atomics.new(1, [])

    deps =
      base_deps(%{
        mk_temp_dir: fn _prefix ->
          workspace = Path.join(System.tmp_dir!(), "agent-provider-smoke-test-#{System.unique_integer([:positive, :monotonic])}")
          File.mkdir_p!(workspace)
          :atomics.put(workspace_ref, 1, :erlang.phash2(workspace))
          send(parent, {:workspace_created, workspace})
          {:ok, workspace}
        end,
        prepare_workspace: fn workspace, opts ->
          send(parent, {:prepare_workspace, workspace, opts})
          :ok
        end,
        start_session: fn workspace, opts ->
          send(parent, {:start_session, workspace, opts})
          {:ok, Session.new(agent_provider_kind: "mock", session_id: "session-1", thread_id: "thread-1", workspace: workspace)}
        end,
        run_turn: fn session, prompt, issue, opts ->
          send(parent, {:run_turn, session, prompt, issue, opts})
          {:ok, TurnResult.new(status: :completed, session_id: "session-1", thread_id: "thread-1", turn_id: "turn-1")}
        end,
        stop_session: fn session, opts ->
          send(parent, {:stop_session, session, opts})
          :ok
        end
      })

    report = Smoke.run([template: TemplateRegistry.local_quickstart_alias()], deps)

    assert report.ok
    assert report.agent_provider_kind == "mock"
    assert report.smoke_mode == "first_turn"
    assert report.prompt_transport == "test_transport"
    assert report.command == ["mock-agent", "serve"]

    assert Enum.map(report.probes, & &1.id) == [
             "config-validation",
             "capability",
             "workspace",
             "prepare-workspace",
             "start-session",
             "run-turn",
             "stop-session",
             "cleanup"
           ]

    assert_receive {:workspace_created, workspace}
    assert_receive {:prepare_workspace, ^workspace, prepare_opts}
    assert_receive {:start_session, ^workspace, start_opts}
    assert_receive {:run_turn, %Session{}, prompt, issue, turn_opts}
    assert_receive {:stop_session, %Session{}, stop_opts}

    assert Keyword.fetch!(prepare_opts, :agent_provider_config).kind == "mock"
    assert Keyword.fetch!(start_opts, :agent_provider_config).kind == "mock"
    assert is_function(Keyword.fetch!(start_opts, :dynamic_tool_workflow_planner), 1)
    assert prompt =~ "Symphony agent-provider smoke check"
    assert issue.identifier == "AGENT-PROVIDER-SMOKE"
    assert Keyword.fetch!(turn_opts, :issue_identifier) == "AGENT-PROVIDER-SMOKE"
    assert Keyword.fetch!(stop_opts, :status) == :completed
    refute File.exists?(workspace)
    assert :atomics.get(workspace_ref, 1) != 0
  end

  test "start-only mode skips the provider turn" do
    parent = self()

    deps =
      base_deps(%{
        start_session: fn workspace, _opts ->
          {:ok, Session.new(agent_provider_kind: "mock", session_id: "session-1", thread_id: "thread-1", workspace: workspace)}
        end,
        run_turn: fn _session, _prompt, _issue, _opts ->
          send(parent, :unexpected_run_turn)
          {:ok, TurnResult.new(status: :completed)}
        end
      })

    report = Smoke.run([template: TemplateRegistry.local_quickstart_alias(), run_turn: false], deps)

    assert report.ok
    assert report.smoke_mode == "start_only"
    refute Enum.any?(report.probes, &(&1.id == "run-turn"))
    refute_received :unexpected_run_turn
  end

  test "config failures skip provider runtime probes" do
    parent = self()

    deps =
      base_deps(%{
        validate_config: fn -> {:error, "bad config"} end,
        prepare_workspace: fn _workspace, _opts ->
          send(parent, :unexpected_prepare)
          :ok
        end
      })

    report = Smoke.run([template: TemplateRegistry.local_quickstart_alias()], deps)

    refute report.ok
    assert Enum.map(report.probes, & &1.id) == ["config-validation"]
    assert hd(report.probes).error == "bad config"
    refute_received :unexpected_prepare
  end

  defp base_deps(overrides) do
    local_quickstart_alias = TemplateRegistry.local_quickstart_alias()

    provider = %Config{
      kind: "mock",
      options: %{
        "command_argv" => ["mock-agent", "serve"],
        "prompt_transport" => "test_transport"
      }
    }

    default_workspace = Path.join(System.tmp_dir!(), "agent-provider-smoke-test-#{System.unique_integer([:positive, :monotonic])}")

    %{
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      workflow_file_path: fn -> "/tmp/WORKFLOW.md" end,
      set_workflow_file_path: fn _path -> :ok end,
      workflow_file_env: fn -> :error end,
      restore_workflow_file_env: fn _previous -> :ok end,
      resolve_template: fn ^local_quickstart_alias -> {:ok, "/tmp/template.md"} end,
      file_regular?: fn _path -> true end,
      validate_config: fn -> :ok end,
      settings: fn -> {:ok, %{agent_provider: provider}} end,
      provider_capabilities: fn ^provider -> ["agent.turn.run"] end,
      mk_temp_dir: fn _prefix ->
        File.mkdir_p!(default_workspace)
        {:ok, default_workspace}
      end,
      prepare_workspace: fn _workspace, _opts -> :ok end,
      start_session: fn workspace, _opts ->
        {:ok, Session.new(agent_provider_kind: "mock", session_id: "session-1", thread_id: "thread-1", workspace: workspace)}
      end,
      run_turn: fn _session, _prompt, _issue, _opts -> {:ok, TurnResult.new(status: :completed, turn_id: "turn-1")} end,
      stop_session: fn _session, _opts -> :ok end,
      rm_rf: &File.rm_rf/1
    }
    |> Map.merge(overrides)
  end

  defp restore_workflow_path({:ok, path}), do: Application.put_env(:symphony_elixir, :workflow_file_path, path)
  defp restore_workflow_path(:error), do: Application.delete_env(:symphony_elixir, :workflow_file_path)
end
