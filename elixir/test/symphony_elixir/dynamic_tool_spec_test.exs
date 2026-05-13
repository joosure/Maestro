defmodule SymphonyElixir.Agent.DynamicTool.SpecTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.BridgeContract
  alias SymphonyElixir.Agent.DynamicTool.CompositeSource
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.Policy
  alias SymphonyElixir.Agent.DynamicTool.Spec
  alias SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin
  alias SymphonyElixir.Tracker.{Linear, Tapd}

  test "bridge contract centralizes external process paths and environment names" do
    assert BridgeContract.base_path() == "/api/v1/agent-tools/dynamic"
    assert BridgeContract.execute_path() == BridgeContract.base_path() <> "/execute"
    assert BridgeContract.base_url_env() == "SYMPHONY_DYNAMIC_TOOL_BRIDGE_BASE_URL"
    assert BridgeContract.token_env() == "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TOKEN"
    assert BridgeContract.transport_env() == "SYMPHONY_DYNAMIC_TOOL_BRIDGE_TRANSPORT"
    assert BridgeContract.token_config_key() == :dynamic_tool_bridge_token
    assert BridgeContract.remote_port_option_key() == :dynamic_tool_bridge_remote_port
    assert BridgeContract.local_transport() == "local_http"
    assert BridgeContract.ssh_tunnel_transport() == "ssh_tunnel_http"
    assert BridgeContract.worker_daemon_transport() == "worker_daemon_http"
  end

  defmodule RepoSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(opts), do: Keyword.get(opts, :repo_source_context, %{})
    def kind(_source_context), do: "repo"

    def tools(_source_context, _opts) do
      [
        %{
          "name" => "shared_tool",
          "description" => "Repo-owned shared tool.",
          "inputSchema" => %{"type" => "object"},
          "schemaVersion" => "1",
          "sideEffect" => "read_only",
          "riskFlags" => ["repo"]
        },
        %{
          "name" => "repo_only_tool",
          "description" => "Repo-only tool.",
          "inputSchema" => %{"type" => "object"},
          "schemaVersion" => "1",
          "sideEffect" => "write",
          "riskFlags" => ["repo"]
        }
      ]
    end

    def environment(_source_context, _opts) do
      %{"REPO_TOOL_ENV" => "enabled", "SHARED_TOOL_ENV" => "repo"}
    end

    def execute(source_context, tool, arguments, _opts) do
      send(source_context.pid, {:repo_source_execute, tool, arguments})
      {:success, %{"source" => "repo", "tool" => tool}}
    end
  end

  defmodule WorkflowSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    def default_context(opts), do: Keyword.get(opts, :workflow_source_context, %{})
    def kind(_source_context), do: "workflow"

    def tools(_source_context, _opts) do
      [
        %{
          "name" => "shared_tool",
          "description" => "Workflow duplicate should lose to repo source.",
          "inputSchema" => %{"type" => "object"},
          "schemaVersion" => "1",
          "sideEffect" => "destructive",
          "riskFlags" => ["workflow"]
        },
        %{
          "name" => "workflow_only_tool",
          "description" => "Workflow-only tool.",
          "inputSchema" => %{"type" => "object"},
          "schemaVersion" => "1",
          "sideEffect" => "read_only",
          "riskFlags" => ["workflow"]
        }
      ]
    end

    def environment(_source_context, _opts) do
      %{"WORKFLOW_TOOL_ENV" => "enabled", "SHARED_TOOL_ENV" => "workflow"}
    end

    def execute(source_context, tool, arguments, _opts) do
      send(source_context.pid, {:workflow_source_execute, tool, arguments})
      {:success, %{"source" => "workflow", "tool" => tool}}
    end
  end

  test "normalize converts portable specs to canonical string-keyed maps" do
    assert {:ok,
            %{
              "name" => "linear_issue_snapshot",
              "description" => "Read a Linear issue snapshot.",
              "inputSchema" => %{
                "type" => "object",
                "required" => ["issue_id"],
                "properties" => %{"issue_id" => %{"type" => "string"}}
              }
            }} =
             Spec.normalize(%{
               name: "linear_issue_snapshot",
               description: " Read a Linear issue snapshot. ",
               inputSchema: %{
                 type: "object",
                 required: ["issue_id"],
                 properties: %{issue_id: %{type: "string"}}
               }
             })
  end

  test "normalize rejects invalid names and non JSON-encodable schema values" do
    assert :error =
             Spec.normalize(%{
               "name" => "../bad",
               "inputSchema" => %{"type" => "object"}
             })

    assert :error =
             Spec.normalize(%{
               "name" => "bad_schema",
               "inputSchema" => %{"type" => "object", "properties" => %{"call" => fn -> :ok end}}
             })
  end

  test "normalize rejects non-object roots and malformed schema collections" do
    assert :error =
             Spec.normalize(%{
               "name" => "bad_root",
               "inputSchema" => %{"type" => "string"}
             })

    assert :error =
             Spec.normalize(%{
               "name" => "bad_required",
               "inputSchema" => %{"type" => "object", "required" => ["query", :variables]}
             })

    assert :error =
             Spec.normalize(%{
               "name" => "bad_properties",
               "inputSchema" => %{"type" => "object", "properties" => ["query"]}
             })
  end

  test "normalize_many drops invalid specs and keeps the first duplicate name" do
    assert [
             %{"name" => "ticket_lookup", "description" => "First.", "inputSchema" => %{"type" => "object"}},
             %{"name" => "typed_tracker_tool"}
           ] =
             Spec.normalize_many([
               %{"name" => "ticket_lookup", "description" => "First.", "inputSchema" => %{"type" => "object"}},
               %{"name" => "ticket_lookup", "description" => "Second.", "inputSchema" => %{"type" => "object"}},
               %{"name" => "bad name", "inputSchema" => %{"type" => "object"}},
               %{"name" => "typed_tracker_tool", "inputSchema" => %{"type" => "object"}}
             ])
  end

  test "dynamic tool context normalizes externally supplied session specs" do
    context =
      Context.from_opts(
        tool_context: %{
          source_context: %{kind: "fake"},
          tool_specs: [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}},
            %{"name" => "invalid tool", "inputSchema" => %{"type" => "object"}}
          ]
        }
      )

    assert [%{"name" => "valid_tool"}] = Context.tool_specs(context)
    assert Context.tool_enabled?(context, "valid_tool")
    refute Context.tool_enabled?(context, "invalid tool")
  end

  test "dynamic tool context captures side-effect metadata outside registration specs" do
    context =
      Context.from_opts(
        tool_context: %{
          source_context: %{kind: "fake"},
          tool_specs: [
            %{
              "name" => "write_tool",
              "description" => "Writes test state.",
              "inputSchema" => %{"type" => "object"},
              "schemaVersion" => "2",
              "sideEffect" => "write",
              "riskFlags" => ["external_network"]
            }
          ]
        }
      )

    assert [%{"name" => "write_tool"} = registration_spec] = Context.tool_specs(context)
    refute Map.has_key?(registration_spec, "sideEffect")

    assert %{
             "sideEffect" => "write",
             "schemaVersion" => "2",
             "riskFlags" => ["external_network"]
           } = context.tool_metadata["write_tool"]

    refute Map.has_key?(context.tool_metadata["write_tool"], "workflowCapability")
    refute Map.has_key?(context.tool_metadata["write_tool"], "sourceKind")

    assert {:error, %{"error" => %{"sideEffect" => "write"}}} =
             Policy.authorize(context, "write_tool", dynamic_tool_policy: %{allowed_side_effects: ["read_only"]})

    assert :ok =
             Policy.authorize(context, "write_tool", dynamic_tool_policy: %{"allowedSideEffects" => ["write"]})
  end

  test "composite source aggregates tools and routes execution to the owning source" do
    context =
      Context.capture(
        dynamic_tool_sources: [
          {RepoSource, %{pid: self()}},
          {WorkflowSource, %{pid: self()}}
        ]
      )

    assert context.source == CompositeSource
    assert context.source_kind == "composite"

    assert [
             %{"name" => "shared_tool"},
             %{"name" => "repo_only_tool"},
             %{"name" => "workflow_only_tool"}
           ] = Context.tool_specs(context)

    assert %{
             "sideEffect" => "read_only",
             "riskFlags" => ["repo"]
           } = context.tool_metadata["shared_tool"]

    assert context.tool_environment == %{
             "REPO_TOOL_ENV" => "enabled",
             "SHARED_TOOL_ENV" => "repo",
             "WORKFLOW_TOOL_ENV" => "enabled"
           }

    assert {:success, %{"source" => "repo", "tool" => "shared_tool"}} =
             DynamicTool.execute(context, "shared_tool", %{"id" => "1"})

    assert_receive {:repo_source_execute, "shared_tool", %{"id" => "1"}}
    refute_received {:workflow_source_execute, "shared_tool", %{"id" => "1"}}

    assert {:success, %{"source" => "workflow", "tool" => "workflow_only_tool"}} =
             DynamicTool.execute(context, "workflow_only_tool", %{"id" => "2"})

    assert_receive {:workflow_source_execute, "workflow_only_tool", %{"id" => "2"}}

    assert {:error, {:unsupported_dynamic_tool, "missing_tool"}} =
             DynamicTool.execute(context, "missing_tool", %{})
  end

  test "provider schema default maps unsupported OpenCode properties to unknown values" do
    source =
      PlannedToolPlugin.render(%{
        "name" => "complex_schema",
        "description" => "Uses a non-portable schema keyword.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "value" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "number"}]}
          }
        }
      })

    assert source =~ ~S|"value": z.unknown().optional()|
  end

  test "OpenCode planned tool plugin preserves bridge failure payloads separately from transport failures" do
    source =
      PlannedToolPlugin.render(%{
        "name" => "failure_mapping_tool",
        "description" => "Checks generated bridge failure mapping.",
        "inputSchema" => %{"type" => "object"}
      })

    bridge_failure_check = "if (!response.ok || payload?.success === false)"
    transport_failure_message = "Symphony Dynamic Tool bridge request failed."

    assert source =~ bridge_failure_check
    assert source =~ transport_failure_message
    assert String.contains?(source, "payload = await readJson(response);\n    } catch (error)")
    assert String.contains?(source, "    }\n\n    #{bridge_failure_check}")
  end

  test "production tracker tools declare side-effect metadata" do
    linear_specs = Map.new(Linear.ToolExecutor.tool_specs(), &{Map.fetch!(&1, "name"), &1})

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "read_only",
             "riskFlags" => ["external_network", "secret_access", "privileged_api"],
             "workflowCapability" => "tracker.issue_snapshot",
             "sourceKind" => "linear"
           } = Map.fetch!(linear_specs, "linear_issue_snapshot")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "riskFlags" => ["external_network", "secret_access", "privileged_api"],
             "workflowCapability" => "tracker.upsert_comment",
             "sourceKind" => "linear"
           } = Map.fetch!(linear_specs, "linear_upsert_comment")

    tapd_specs = Map.new(Tapd.ToolExecutor.tool_specs(), &{Map.fetch!(&1, "name"), &1})

    refute Map.has_key?(tapd_specs, "tapd_api")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "riskFlags" => ["external_network", "secret_access", "privileged_api"],
             "workflowCapability" => "tracker.create_follow_up_issue",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_create_follow_up_story")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "read_only",
             "workflowCapability" => "tracker.read_issue_dependencies",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_read_story_dependencies")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "workflowCapability" => "tracker.save_issue_dependency",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_save_story_dependency")
  end
end
