defmodule SymphonyElixir.Agent.DynamicTool.SpecTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.DynamicTool
  alias SymphonyElixir.Agent.DynamicTool.Bridge
  alias SymphonyElixir.Agent.DynamicTool.CompositeSource
  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Agent.DynamicTool.Metadata
  alias SymphonyElixir.Agent.DynamicTool.Policy
  alias SymphonyElixir.Agent.DynamicTool.Spec
  alias SymphonyElixir.Agent.DynamicTool.ToolSpec
  alias SymphonyElixir.AgentProvider.OpenCode.Tooling.PlannedToolPlugin
  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Platform.DynamicToolBridgeContract, as: BridgeContract
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response
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
    assert Response.success(%{"ok" => true}) == %{"success" => true, "payload" => %{"ok" => true}}
    assert Response.error("bad") == %{"success" => false, "payload" => %{"error" => %{"message" => "bad"}}}
    assert Response.error_payload("invalid", "bad") == %{"error" => %{"code" => "invalid", "message" => "bad"}}
    assert Response.reason_key() == "reason"
    assert Response.result_key() == "result"
    assert EventContract.dynamic_tool_bridge_component() == "agent.dynamic_tool_bridge"
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
          "capability" => "test.shared",
          "schemaVersion" => "1",
          "sideEffect" => "read_only",
          "riskFlags" => ["repo"]
        },
        %{
          "name" => "repo_only_tool",
          "description" => "Repo-only tool.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.repo_only",
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
          "capability" => "test.shared_duplicate",
          "schemaVersion" => "1",
          "sideEffect" => "destructive",
          "riskFlags" => ["workflow"]
        },
        %{
          "name" => "workflow_only_tool",
          "description" => "Workflow-only tool.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.workflow_only",
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

  defmodule AliasSource do
    @behaviour SymphonyElixir.Agent.DynamicTool.Source

    alias SymphonyElixir.Agent.DynamicTool.Metadata

    @canonical_tool "canonical_probe"
    @provider_tool "provider_probe"

    def default_context(opts), do: Keyword.get(opts, :alias_source_context, %{})
    def kind(_source_context), do: "alias_test"

    def tools(_source_context, _opts) do
      [
        %{
          "name" => @canonical_tool,
          "description" => "Canonical probe.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.alias_probe",
          "schemaVersion" => "1",
          "sideEffect" => "read_only"
        },
        %{
          "name" => @provider_tool,
          "description" => "Provider-facing probe alias.",
          "inputSchema" => %{"type" => "object"},
          "capability" => "test.alias_probe",
          "schemaVersion" => "1",
          "sideEffect" => "read_only",
          Metadata.Contract.tool_alias_of() => @canonical_tool
        }
      ]
    end

    def environment(_source_context, _opts), do: %{}

    def canonical_tool(_source_context, @provider_tool), do: @canonical_tool
    def canonical_tool(_source_context, tool), do: tool

    def execute(source_context, tool, arguments, opts) do
      send(source_context.pid, {:alias_source_execute, tool, arguments, opts})
      {:success, %{"tool" => tool, "arguments" => arguments}}
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
               "name" => "linear_issue_snapshot",
               "description" => " Read a Linear issue snapshot. ",
               "inputSchema" => %{
                 "type" => "object",
                 "required" => ["issue_id"],
                 "properties" => %{"issue_id" => %{"type" => "string"}}
               }
             })
  end

  test "normalize only accepts canonical string-key specs and schemas" do
    assert :error =
             Spec.normalize(%{
               name: "atom_key_tool",
               description: "Atom-key tool spec.",
               inputSchema: %{"type" => "object"}
             })

    assert :error =
             Spec.normalize(%{
               "name" => "snake_schema_tool",
               "description" => "Snake schema tool spec.",
               "input_schema" => %{"type" => "object"}
             })

    assert :error =
             Spec.normalize(%{
               "name" => "atom_schema_key_tool",
               "description" => "Atom schema key tool spec.",
               "inputSchema" => %{type: "object"}
             })
  end

  test "unsupported diagnostics do not project atom-key tool specs" do
    atom_key_context = %{
      "source" => SymphonyElixir.Agent.DynamicTool.CompositeSource,
      "tool_specs" => [
        %{
          name: "atom_key_tool",
          description: "Atom-key tool spec.",
          inputSchema: %{"type" => "object"}
        }
      ],
      "tool_metadata" => %{}
    }

    assert {:failure, %{"error" => %{"code" => "unsupported_tool", "supportedTools" => supported_tools}}} =
             DynamicTool.execute(atom_key_context, "missing_tool", %{})

    assert supported_tools == []
    refute "atom_key_tool" in supported_tools
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

    assert :error =
             Spec.normalize(%{
               "name" => "bad_nested_property",
               "inputSchema" => %{"type" => "object", "properties" => %{"query" => %{"type" => :string}}}
             })
  end

  test "normalize_many_strict returns diagnostics for invalid and duplicate specs" do
    assert {:error,
            [
              %ToolSpec.Error{index: 1, reason: {:duplicate_name, "ticket_lookup"}, tool_name: "ticket_lookup"},
              %ToolSpec.Error{index: 2, reason: :invalid_spec}
            ]} =
             Spec.normalize_many_strict([
               %{"name" => "ticket_lookup", "description" => "First.", "inputSchema" => %{"type" => "object"}},
               %{"name" => "ticket_lookup", "description" => "Second.", "inputSchema" => %{"type" => "object"}},
               %{"name" => "bad name", "inputSchema" => %{"type" => "object"}}
             ])

    assert {:error, [%ToolSpec.Error{index: nil, reason: :invalid_collection}]} =
             Spec.normalize_many_strict(:not_a_list)

    assert {:ok, [%{"name" => "valid_tool"}]} =
             Spec.normalize_many_strict([
               %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}}
             ])
  end

  test "dynamic tool context normalizes externally supplied session specs" do
    context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}}
          ]
        }
      )

    assert [%{"name" => "valid_tool"}] = Context.tool_specs(context)
    assert Context.tool_enabled?(context, "valid_tool")
  end

  test "dynamic tool context fails closed on invalid external source or tool specs" do
    invalid_spec_context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}},
            %{"name" => "invalid tool", "inputSchema" => %{"type" => "object"}}
          ]
        }
      )

    assert Context.tool_specs(invalid_spec_context) == []

    invalid_source_context =
      Context.from_opts(
        tool_context: %{
          "source" => String,
          "source_context" => %{"tool_specs" => []},
          "tool_specs" => [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}}
          ]
        }
      )

    assert Context.tool_specs(invalid_source_context) == []
  end

  test "dynamic tool context rejects atom-key runtime metadata payloads" do
    context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}}
          ],
          "runtime_metadata" => %{run_id: "run-1"}
        }
      )

    assert Context.tool_specs(context) == []
  end

  test "dynamic tool context normalizes source and trims metadata to enabled tools" do
    assert %CompositeSource.Context{} = Context.empty().source_context

    context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"tool_specs" => []},
          "tool_specs" => [
            %{"name" => "valid_tool", "inputSchema" => %{"type" => "object"}}
          ],
          "tool_metadata" => %{
            "valid_tool" => %{"sideEffect" => "read_only", "capability" => "test.valid"},
            "ghost_tool" => %{"sideEffect" => "write", "capability" => "test.ghost"}
          }
        }
      )

    assert context.source == CompositeSource
    assert %CompositeSource.Context{} = context.source_context
    assert [%{"name" => "valid_tool"}] = Context.tool_specs(context)

    assert %{"valid_tool" => %{"capability" => "test.valid", "sideEffect" => "read_only"}} =
             Context.tool_metadata(context)

    refute Map.has_key?(Context.tool_metadata(context), "ghost_tool")
  end

  test "dynamic tool context captures side-effect metadata outside registration specs" do
    context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
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

    tool_metadata = Context.tool_metadata(context)

    assert %{
             "sideEffect" => "write",
             "schemaVersion" => "2",
             "riskFlags" => ["external_network"]
           } = tool_metadata["write_tool"]

    refute Map.has_key?(tool_metadata["write_tool"], "capability")
    refute Map.has_key?(tool_metadata["write_tool"], "sourceKind")

    assert {:error, %Policy.Decision{details: %{"sideEffect" => "write"}}} =
             Policy.authorize(context, "write_tool", Policy.Config.new!(allowed_side_effects: ["read_only"]))

    assert :ok =
             Policy.authorize(context, "write_tool", Policy.Config.new!(allowed_side_effects: ["write"]))
  end

  test "dynamic tool policy config is a stable internal structure" do
    assert {:error, %Policy.Error{reason: :invalid_policy_config}} =
             Policy.Config.from_opts(dynamic_tool_policy: %{allowed_side_effects: ["read_only"]})

    assert {:error, %Policy.Error{reason: :invalid_allowed_side_effects}} =
             Policy.Config.new(allowed_side_effects: ["readonly"])

    assert {:ok, %Policy.Config{allowed_side_effects: ["read_only"]}} =
             Policy.Config.from_opts(dynamic_tool_policy: Policy.Config.new!(allowed_side_effects: ["read_only"]))
  end

  test "dynamic tool metadata accepts only canonical string keys" do
    context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{
              "name" => "snake_case_metadata_tool",
              "description" => "Uses non-canonical metadata keys.",
              "inputSchema" => %{"type" => "object"},
              "capability" => "test.snake_case_metadata",
              "side_effect" => "read_only",
              "source_kind" => "fake",
              "schema_version" => "2",
              "risk_flags" => ["legacy"],
              "operator_only" => true
            },
            %{
              "name" => "atom_metadata_tool",
              "description" => "Uses atom metadata keys.",
              "inputSchema" => %{"type" => "object"},
              capability: "test.atom_metadata",
              sideEffect: "read_only",
              sourceKind: "fake",
              schemaVersion: "2",
              riskFlags: ["legacy"],
              operatorOnly: true
            },
            %{
              "name" => "atom_metadata_value_tool",
              "description" => "Uses atom metadata values.",
              "inputSchema" => %{"type" => "object"},
              "capability" => :atom_capability,
              "sideEffect" => :read_only,
              "sourceKind" => :fake,
              "schemaVersion" => :v2,
              "riskFlags" => [:legacy],
              "operatorOnly" => :operator_only
            }
          ]
        }
      )

    snake_metadata = Context.metadata_for(context, "snake_case_metadata_tool")

    assert snake_metadata.capability == "test.snake_case_metadata"
    assert snake_metadata.side_effect == nil
    assert Metadata.side_effect_error(snake_metadata) == :missing
    assert snake_metadata.source_kind == nil
    assert snake_metadata.schema_version == "1"
    assert snake_metadata.risk_flags == []
    refute snake_metadata.operator_only?

    atom_metadata = Context.metadata_for(context, "atom_metadata_tool")

    assert atom_metadata.capability == nil
    assert atom_metadata.side_effect == nil
    assert Metadata.side_effect_error(atom_metadata) == :missing
    assert atom_metadata.source_kind == nil
    assert atom_metadata.schema_version == "1"
    assert atom_metadata.risk_flags == []
    refute atom_metadata.operator_only?

    atom_value_metadata = Context.metadata_for(context, "atom_metadata_value_tool")

    assert atom_value_metadata.capability == nil
    assert atom_value_metadata.side_effect == nil
    assert Metadata.side_effect_error(atom_value_metadata) == {:invalid, ":read_only"}
    assert atom_value_metadata.source_kind == nil
    assert atom_value_metadata.schema_version == "1"
    assert atom_value_metadata.risk_flags == []
    refute atom_value_metadata.operator_only?
  end

  test "dynamic tool execution rejects non-canonical side-effect metadata before source execution" do
    invalid_context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{
              "name" => "legacy_read_tool",
              "description" => "Uses a non-canonical legacy side-effect value.",
              "inputSchema" => %{"type" => "object"},
              "capability" => "test.legacy_read",
              "sideEffect" => "readonly"
            }
          ]
        }
      )

    refute Map.has_key?(Context.tool_metadata(invalid_context)["legacy_read_tool"], "sideEffect")

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_dynamic_tool_metadata",
                "field" => "sideEffect",
                "reason" => "invalid",
                "value" => "readonly",
                "allowedValues" => ["read_only", "write", "destructive"]
              }
            }} = DynamicTool.execute(invalid_context, "legacy_read_tool", %{})

    missing_context =
      Context.from_opts(
        tool_context: %{
          "source_context" => %{"kind" => "fake"},
          "tool_specs" => [
            %{
              "name" => "missing_side_effect_tool",
              "description" => "Omits required side-effect metadata.",
              "inputSchema" => %{"type" => "object"},
              "capability" => "test.missing_side_effect"
            }
          ]
        }
      )

    assert {:failure,
            %{
              "error" => %{
                "code" => "invalid_dynamic_tool_metadata",
                "field" => "sideEffect",
                "reason" => "missing",
                "allowedValues" => ["read_only", "write", "destructive"]
              }
            }} = DynamicTool.execute(missing_context, "missing_side_effect_tool", %{})
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
           } = Context.tool_metadata(context)["shared_tool"]

    assert context.tool_environment == %{
             "REPO_TOOL_ENV" => "enabled",
             "SHARED_TOOL_ENV" => "repo",
             "WORKFLOW_TOOL_ENV" => "enabled"
           }

    assert [
             %CompositeSource.Conflict{
               tool: "shared_tool",
               kept_route: %CompositeSource.Route{source: RepoSource, source_kind: "repo"},
               rejected_route: %CompositeSource.Route{source: WorkflowSource, source_kind: "workflow"}
             }
           ] = CompositeSource.conflicts(context.source_context)

    assert {:success, %{"source" => "repo", "tool" => "shared_tool"}} =
             DynamicTool.execute(context, "shared_tool", %{"id" => "1"})

    assert_receive {:repo_source_execute, "shared_tool", %{"id" => "1"}}
    refute_received {:workflow_source_execute, "shared_tool", %{"id" => "1"}}

    assert {:success, %{"source" => "workflow", "tool" => "workflow_only_tool"}} =
             DynamicTool.execute(context, "workflow_only_tool", %{"id" => "2"})

    assert_receive {:workflow_source_execute, "workflow_only_tool", %{"id" => "2"}}

    assert {:failure, %{"error" => %{"code" => "unsupported_tool", "supportedTools" => supported_tools}}} =
             DynamicTool.execute(context, "missing_tool", %{})

    assert "repo_only_tool" in supported_tools
    assert "workflow_only_tool" in supported_tools

    restricted = Context.restrict_tools(context, ["repo_only_tool"])

    assert [%{"name" => "repo_only_tool"}] = Context.tool_specs(restricted)
    assert [] = CompositeSource.conflicts(restricted.source_context)
    refute Map.has_key?(restricted.source_context.routes, "shared_tool")
  end

  test "bridge executes provider aliases as canonical tools and records both names" do
    EventStore.reset()
    on_exit(fn -> EventStore.reset() end)

    context =
      DynamicTool.capture_context(dynamic_tool_sources: [{AliasSource, %{pid: self()}}])

    assert %{"success" => true, "payload" => %{"tool" => "canonical_probe", "arguments" => %{"id" => "1"}}} =
             Bridge.execute("provider_probe", %{"id" => "1"}, tool_context: context)

    assert_receive {:alias_source_execute, "canonical_probe", %{"id" => "1"}, source_opts}
    assert Keyword.fetch!(source_opts, :tool_context) == context
    assert Keyword.fetch!(source_opts, :provider_tool_name) == "provider_probe"
    assert Keyword.fetch!(source_opts, :canonical_tool_name) == "canonical_probe"

    event =
      EventStore.recent_events(limit: 10)
      |> Enum.find(&(&1["event"] == "tool_call_succeeded" and &1["tool_name"] == "provider_probe"))

    assert event["provider_tool_name"] == "provider_probe"
    assert event["canonical_tool_name"] == "canonical_probe"
    assert event["dynamic_tool_capability"] == "test.alias_probe"
  end

  test "composite canonical execution rejects provider and canonical mismatches" do
    context =
      DynamicTool.capture_context(dynamic_tool_sources: [{AliasSource, %{pid: self()}}])

    assert {:error, {:canonical_dynamic_tool_mismatch, "provider_probe", "wrong_probe", "canonical_probe"}} =
             CompositeSource.execute_canonical(context.source_context, "provider_probe", "wrong_probe", %{}, [])

    refute_received {:alias_source_execute, _tool, _arguments, _opts}
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
             "capability" => "tracker.issue_snapshot",
             "sourceKind" => "linear"
           } = Map.fetch!(linear_specs, "linear_issue_snapshot")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "riskFlags" => ["external_network", "secret_access", "privileged_api"],
             "capability" => "tracker.upsert_comment",
             "sourceKind" => "linear"
           } = Map.fetch!(linear_specs, "linear_upsert_comment")

    tapd_specs = Map.new(Tapd.ToolExecutor.tool_specs(), &{Map.fetch!(&1, "name"), &1})

    refute Map.has_key?(tapd_specs, "tapd_api")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "riskFlags" => ["external_network", "secret_access", "privileged_api"],
             "capability" => "tracker.create_follow_up_issue",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_create_follow_up_story")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "read_only",
             "capability" => "tracker.read_issue_dependencies",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_read_story_dependencies")

    assert %{
             "schemaVersion" => "1",
             "sideEffect" => "write",
             "capability" => "tracker.save_issue_dependency",
             "sourceKind" => "tapd"
           } = Map.fetch!(tapd_specs, "tapd_save_story_dependency")
  end
end
