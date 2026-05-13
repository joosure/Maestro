defmodule SymphonyElixir.Agent.DynamicTool.InventoryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.AgentProvider.ToolInventory

  test "resolves required typed capabilities to exactly one non-deprecated tool" do
    context = tool_context()

    assert {:ok,
            [
              %{
                capability: "tracker.issue_snapshot",
                tool: "linear_issue_snapshot",
                side_effect: "read_only",
                source_kind: "linear",
                schema_version: "1",
                deprecated?: false
              }
            ]} = Inventory.resolve_required(context, ["tracker.issue_snapshot"])
  end

  test "rejects missing and ambiguous typed capability mappings" do
    assert {:error, {:missing_typed_workflow_tool, "tracker.move_issue"}} =
             Inventory.resolve_required(tool_context(), ["tracker.move_issue"])

    ambiguous =
      put_in(tool_context(), [:tool_metadata, "second_snapshot"], %{
        "workflowCapability" => "tracker.issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })
      |> update_in([:tool_specs], &(&1 ++ [%{"name" => "second_snapshot", "inputSchema" => %{"type" => "object"}}]))

    assert {:error, {:ambiguous_typed_workflow_tool, "tracker.issue_snapshot", ["linear_issue_snapshot", "second_snapshot"]}} =
             Inventory.resolve_required(ambiguous, ["tracker.issue_snapshot"])
  end

  test "ignores deprecated typed tools when resolving and rendering inventory" do
    context =
      tool_context()
      |> add_tool("old_linear_issue_snapshot", %{
        "workflowCapability" => "tracker.issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1",
        "deprecated" => true
      })

    assert {:ok, [%{tool: "linear_issue_snapshot", deprecated?: false}]} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"])

    inventory = Inventory.render(context)

    assert inventory =~ "`linear_issue_snapshot`"
    refute inventory =~ "old_linear_issue_snapshot"
  end

  test "rejects a required typed capability when only deprecated typed tools exist" do
    context =
      put_in(tool_context(), [:tool_metadata, "linear_issue_snapshot", "deprecated"], true)

    assert {:error, {:missing_typed_workflow_tool, "tracker.issue_snapshot"}} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"])
  end

  test "allows operator migration fallback only when policy names an advertised runtime tool" do
    policy = %{
      "tracker.issue_snapshot" => %{
        "tool" => "legacy_tracker_api",
        "reason" => "temporary provider migration"
      }
    }

    assert {:ok,
            [
              %{
                capability: "tracker.issue_snapshot",
                tool: "legacy_tracker_api",
                side_effect: "destructive",
                source_kind: "linear",
                fallback?: true,
                fallback_reason: "temporary provider migration"
              }
            ]} =
             Inventory.resolve_required(raw_only_tool_context(), ["tracker.issue_snapshot"], fallback_policy: policy)

    inventory = Inventory.render(raw_only_tool_context(), fallback_policy: policy)

    assert inventory =~ "`tracker.issue_snapshot`"
    assert inventory =~ "`legacy_tracker_api`"
    assert inventory =~ "explicit operator migration fallback permitted: temporary provider migration"
  end

  test "rejects operator migration fallback policy when the fallback tool is missing or deprecated" do
    assert {:error, {:missing_fallback_workflow_tool, "tracker.issue_snapshot", "missing_tool"}} =
             Inventory.resolve_required(raw_only_tool_context(), ["tracker.issue_snapshot"], fallback_policy: %{"tracker.issue_snapshot" => "missing_tool"})

    deprecated_raw =
      put_in(raw_only_tool_context(), [:tool_metadata, "legacy_tracker_api", "deprecated"], true)

    assert {:error, {:deprecated_fallback_workflow_tool, "tracker.issue_snapshot", "legacy_tracker_api"}} =
             Inventory.resolve_required(deprecated_raw, ["tracker.issue_snapshot"], fallback_policy: %{"tracker.issue_snapshot" => "legacy_tracker_api"})
  end

  test "rejects operator migration fallback policy that points at another typed workflow tool" do
    context =
      raw_only_tool_context()
      |> add_tool("linear_move_issue", %{
        "workflowCapability" => "tracker.move_issue",
        "sideEffect" => "write",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error, {:typed_fallback_workflow_tool, "tracker.issue_snapshot", "linear_move_issue", "tracker.move_issue"}} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"], fallback_policy: %{"tracker.issue_snapshot" => "linear_move_issue"})
  end

  test "does not use operator migration fallback to hide ambiguous typed tool mappings" do
    ambiguous =
      tool_context()
      |> add_tool("second_snapshot", %{
        "workflowCapability" => "tracker.issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error, {:ambiguous_typed_workflow_tool, "tracker.issue_snapshot", ["linear_issue_snapshot", "second_snapshot"]}} =
             Inventory.resolve_required(ambiguous, ["tracker.issue_snapshot"], fallback_policy: %{"tracker.issue_snapshot" => "legacy_tracker_api"})
  end

  test "renders an agent-facing inventory with exact runtime tool names" do
    inventory = Inventory.render(tool_context())

    assert inventory =~ "## Typed Workflow Tool Inventory"
    assert inventory =~ "`tracker.issue_snapshot`"
    assert inventory =~ "`linear_issue_snapshot`"
    assert inventory =~ "Do not guess provider API fields"
    assert inventory =~ "the typed tool arguments and retry that same typed tool"
  end

  test "renders Claude Code MCP callable names for typed tools" do
    inventory = Inventory.render(tool_context(), ToolInventory.render_opts("claude_code"))

    assert inventory =~ "`mcp__symphony-planned-tools__linear_issue_snapshot`"
    assert inventory =~ "| `tracker.issue_snapshot` | `mcp__symphony-planned-tools__linear_issue_snapshot` | `linear_issue_snapshot` |"
    assert inventory =~ "provider-facing callable tool names"
    assert inventory =~ "Claude Code exposes Symphony Dynamic Tools through MCP"
    assert inventory =~ "the typed tool arguments and retry that same typed tool"
  end

  test "Claude Code provider adapter supplies inventory callable naming" do
    opts = ToolInventory.render_opts("claude_code")

    assert is_function(Keyword.fetch!(opts, :provider_callable_name), 1)
    assert Keyword.fetch!(opts, :provider_callable_name).("repo_checkout") == "mcp__symphony-planned-tools__repo_checkout"
    assert Keyword.fetch!(opts, :provider_callable_label) == "Claude Code MCP tool"
  end

  test "Codex provider adapter supplies MCP inventory callable naming" do
    inventory = Inventory.render(tool_context(), ToolInventory.render_opts("codex"))
    opts = ToolInventory.render_opts("codex")

    assert inventory =~ "`mcp__symphony-planned-tools__linear_issue_snapshot`"
    assert inventory =~ "Codex exposes Symphony Dynamic Tools through the runtime MCP bridge"
    assert is_function(Keyword.fetch!(opts, :provider_callable_name), 1)
    assert Keyword.fetch!(opts, :provider_callable_name).("repo_checkout") == "mcp__symphony-planned-tools__repo_checkout"
    assert Keyword.fetch!(opts, :provider_callable_label) == "Codex MCP tool"
  end

  test "raw provider tools do not satisfy typed capabilities without operator migration fallback policy" do
    assert {:error, {:missing_typed_workflow_tool, "tracker.issue_snapshot"}} =
             Inventory.resolve_required(raw_only_tool_context(), ["tracker.issue_snapshot"])
  end

  test "recognizes repo-provider review comment capabilities as typed workflow tools" do
    assert Inventory.typed_capability?("repo.add_change_proposal_comment")
    assert Inventory.typed_capability?("repo.reply_change_proposal_review_comment")
  end

  test "recognizes TAPD raw-fallback replacement capabilities as typed workflow tools" do
    assert Inventory.typed_capability?("tracker.create_follow_up_issue")
    assert Inventory.typed_capability?("tracker.read_issue_relations")
    assert Inventory.typed_capability?("tracker.add_issue_relation")
    assert Inventory.typed_capability?("tracker.read_issue_dependencies")
    assert Inventory.typed_capability?("tracker.save_issue_dependency")
  end

  defp tool_context do
    %{
      tool_specs: [
        %{
          "name" => "linear_issue_snapshot",
          "description" => "Read issue snapshot.",
          "inputSchema" => %{"type" => "object"}
        },
        %{
          "name" => "legacy_tracker_api",
          "description" => "Raw fallback.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_metadata: %{
        "linear_issue_snapshot" => %{
          "workflowCapability" => "tracker.issue_snapshot",
          "sideEffect" => "read_only",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        },
        "legacy_tracker_api" => %{
          "sideEffect" => "destructive",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        }
      }
    }
  end

  defp raw_only_tool_context do
    %{
      tool_specs: [
        %{
          "name" => "legacy_tracker_api",
          "description" => "Raw fallback.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      tool_metadata: %{
        "legacy_tracker_api" => %{
          "sideEffect" => "destructive",
          "sourceKind" => "linear",
          "schemaVersion" => "1"
        }
      }
    }
  end

  defp add_tool(context, tool_name, metadata) do
    context
    |> update_in([:tool_specs], &(&1 ++ [%{"name" => tool_name, "inputSchema" => %{"type" => "object"}}]))
    |> put_in([:tool_metadata, tool_name], metadata)
  end
end
