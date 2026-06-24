defmodule SymphonyElixir.TrackerRegistryTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Agent.DynamicTool.Policy
  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge
  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract
  alias SymphonyElixir.Tracker.Kinds
  alias SymphonyElixir.Tracker.ProjectRef

  defmodule FakeAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter

    alias SymphonyElixir.Tracker.ProjectRef

    @tool_spec %{
      "name" => "fake_tracker_tool",
      "description" => "Fake tracker tool used by registry tests.",
      "capability" => "test.fake_tracker_tool",
      "schemaVersion" => "1",
      "sideEffect" => "write",
      "riskFlags" => ["test_only"],
      "inputSchema" => %{
        "type" => "object",
        "additionalProperties" => true
      }
    }

    def kind, do: "fake"
    def fetch_candidate_issues(_tracker, _opts \\ []), do: {:ok, []}
    def fetch_issues_by_states(_tracker, _states, _opts \\ []), do: {:ok, []}
    def fetch_issue_states_by_ids(_tracker, _issue_ids, _opts \\ []), do: {:ok, []}
    def create_comment(_tracker, _issue_id, _body, _opts \\ []), do: :ok
    def update_issue_state(_tracker, _issue_id, _state_name, _opts \\ []), do: :ok
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok

    def capabilities,
      do: ["tracker.issue.read", "tracker.comment.read", "tracker.comment.write", "tracker.state.update"]

    def dynamic_tools(_tracker), do: [@tool_spec]
    def tool_environment(_tracker), do: %{"FAKE_TRACKER_TOOL_ENV" => "enabled"}
    def project_ref(_tracker), do: %ProjectRef{kind: kind(), id: "fake-project", url: "https://example.test/fake-project"}

    def execute_dynamic_tool(_tracker, tool, arguments, _opts) do
      send(self(), {:fake_tracker_tool_called, tool, arguments})

      case arguments do
        %{"mode" => "native_payload"} ->
          {:success, %{tool: tool, status: :ok, tuple: {:fake, 1}}}

        _arguments ->
          {:success, %{"tool" => tool}}
      end
    end

    def prepare_workspace(_tracker, workspace, opts \\ []) do
      worker_host = Keyword.get(opts, :worker_host)
      send(self(), {:fake_prepare_workspace_called, workspace, worker_host})
      :ok
    end
  end

  defmodule FakeCoreAdapter do
    @behaviour SymphonyElixir.Tracker.Adapter
    alias SymphonyElixir.Tracker.ProjectRef

    def kind, do: "fake_core"
    def fetch_candidate_issues(_tracker, _opts \\ []), do: {:ok, []}
    def fetch_issues_by_states(_tracker, _states, _opts \\ []), do: {:ok, []}
    def fetch_issue_states_by_ids(_tracker, _issue_ids, _opts \\ []), do: {:ok, []}
    def create_comment(_tracker, _issue_id, _body, _opts \\ []), do: :ok
    def update_issue_state(_tracker, _issue_id, _state_name, _opts \\ []), do: :ok
    def defaults, do: %{}
    def validate_config(_tracker), do: :ok
    def project_ref(_tracker), do: %ProjectRef{kind: kind(), id: "fake-core-project"}
  end

  test "registry merges configured adapters and facade delegates to the configured tracker adapter" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"fake" => FakeAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "fake",
      tracker_endpoint: nil,
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil
    )

    assert Tracker.supported_kinds() |> Enum.sort() == ["fake" | Kinds.built_in()] |> Enum.sort()
    assert Tracker.adapter() == FakeAdapter
    assert Tracker.adapter_for("fake") == FakeAdapter
    assert :ok = Config.validate!()
    assert [%{"name" => "fake_tracker_tool"}] = Tracker.dynamic_tools()
    assert %{"FAKE_TRACKER_TOOL_ENV" => "enabled"} = Tracker.tool_environment()

    assert [%{"name" => "fake_tracker_tool"}] =
             DynamicTool.tool_specs(dynamic_tool_source: SymphonyElixir.Tracker.DynamicToolSource)

    assert %ProjectRef{
             kind: "fake",
             id: "fake-project",
             url: "https://example.test/fake-project"
           } = Tracker.project_ref()

    assert :ok = Tracker.prepare_workspace("/tmp/fake-tracker", nil)
    assert_receive {:fake_prepare_workspace_called, "/tmp/fake-tracker", nil}

    assert {:success, %{"tool" => "fake_tracker_tool"}} =
             Tracker.execute_dynamic_tool("fake_tracker_tool", %{"scope" => "registry"})

    assert_receive {:fake_tracker_tool_called, "fake_tracker_tool", %{"scope" => "registry"}}
  end

  test "dynamic tool bridge executes through the tracker facade with provider-neutral env" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"fake" => FakeAdapter})
    Application.put_env(:symphony_elixir, BridgeContract.token_config_key(), "bridge-token")
    Application.put_env(:symphony_elixir, :dynamic_tool_source, SymphonyElixir.Tracker.DynamicToolSource)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
      Application.delete_env(:symphony_elixir, BridgeContract.token_config_key())
      Application.delete_env(:symphony_elixir, :dynamic_tool_source)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "fake",
      tracker_endpoint: nil,
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: nil,
      tracker_terminal_states: nil
    )

    assert {:ok, bridge_env} = DynamicToolBridge.runtime_env(http_port: 4521)
    assert bridge_env[BridgeContract.base_url_env()] == "http://127.0.0.1:4521#{BridgeContract.base_path()}"
    assert bridge_env[BridgeContract.token_env()] == "bridge-token"
    assert bridge_env[BridgeContract.transport_env()] == BridgeContract.local_transport()

    assert Bridge.valid_token?("bridge-token")
    refute Bridge.valid_token?("wrong-token")

    assert %{"success" => true, "payload" => %{"tool" => "fake_tracker_tool"}} =
             Bridge.execute("fake_tracker_tool", %{"scope" => "bridge"})

    assert_receive {:fake_tracker_tool_called, "fake_tracker_tool", %{"scope" => "bridge"}}

    assert %{
             "success" => true,
             "payload" => %{"tool" => "fake_tracker_tool", "status" => "ok", "tuple" => "{:fake, 1}"}
           } = Bridge.execute("fake_tracker_tool", %{"mode" => "native_payload"})

    assert_receive {:fake_tracker_tool_called, "fake_tracker_tool", %{"mode" => "native_payload"}}

    assert %{
             "success" => false,
             "payload" => %{
               "error" => %{
                 "code" => "dynamic_tool_side_effect_denied",
                 "message" => "Dynamic tool side-effect class is not allowed by policy.",
                 "tool" => "fake_tracker_tool",
                 "sideEffect" => "write",
                 "allowedSideEffects" => ["read_only"]
               }
             }
           } =
             Bridge.execute("fake_tracker_tool", %{}, dynamic_tool_policy: Policy.Config.new!(allowed_side_effects: ["read_only"]))

    refute_received {:fake_tracker_tool_called, "fake_tracker_tool", %{}}

    assert %{
             "success" => false,
             "payload" => %{"error" => %{"supportedTools" => ["fake_tracker_tool"]}}
           } = Bridge.execute("missing_tool", %{})
  end

  test "tracker facade exposes safe defaults for optional capabilities" do
    Application.put_env(:symphony_elixir, :tracker_adapters, %{"fake_core" => FakeCoreAdapter})

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :tracker_adapters)
    end)

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "fake_core",
      tracker_endpoint: nil,
      tracker_api_token: nil,
      tracker_api_secret: nil,
      tracker_project_slug: nil,
      tracker_assignee: nil,
      tracker_active_states: [],
      tracker_terminal_states: []
    )

    assert Tracker.adapter() == FakeCoreAdapter
    assert [] = Tracker.dynamic_tools()
    assert %{} = Tracker.tool_environment()
    assert :ok = Tracker.prepare_workspace("/tmp/fake-core-tracker", nil)

    assert {:error,
            %Tracker.Error{
              provider: "fake_core",
              operation: :execute_dynamic_tool,
              code: :unsupported_dynamic_tool,
              message: "Configured tracker does not expose dynamic tools."
            }} = Tracker.execute_dynamic_tool("missing_tool", %{})
  end
end
