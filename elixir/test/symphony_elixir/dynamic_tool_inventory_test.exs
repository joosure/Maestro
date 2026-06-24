defmodule SymphonyElixir.Agent.DynamicTool.InventoryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Inventory
  alias SymphonyElixir.Agent.DynamicTool.Inventory.{RenderOptions, ResolutionError, ResolvedTool}
  alias SymphonyElixir.AgentProvider.ToolInventory

  test "resolves required typed capabilities to exactly one advertised canonical tool" do
    context = tool_context()

    assert {:ok,
            [
              %{
                capability: "tracker.issue_snapshot",
                tool: "linear_issue_snapshot",
                side_effect: "read_only",
                source_kind: "linear",
                schema_version: "1"
              }
            ]} = Inventory.resolve_required(context, ["tracker.issue_snapshot"])
  end

  test "rejects missing and ambiguous typed capability mappings" do
    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.move_issue"}} =
             Inventory.resolve_required(tool_context(), ["tracker.move_issue"])

    ambiguous =
      put_in(tool_context(), ["tool_metadata", "second_snapshot"], %{
        "capability" => "tracker.issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })
      |> update_in(["tool_specs"], &(&1 ++ [%{"name" => "second_snapshot", "inputSchema" => %{"type" => "object"}}]))

    assert {:error,
            %ResolutionError{
              reason: :ambiguous_typed_tool,
              capability: "tracker.issue_snapshot",
              tools: ["linear_issue_snapshot", "second_snapshot"]
            }} =
             Inventory.resolve_required(ambiguous, ["tracker.issue_snapshot"])
  end

  test "retired tools must be omitted by the source instead of marked in metadata" do
    context = raw_only_tool_context()

    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.issue_snapshot"}} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"])

    inventory = Inventory.render(context)

    assert inventory =~ "No typed tools are advertised"
    refute inventory =~ "linear_issue_snapshot"
  end

  test "renders only authoritative canonical typed tools and omits aliases" do
    context =
      tool_context()
      |> add_tool("linear_issue_snapshot_alias", %{
        "capability" => "tracker.issue_snapshot",
        "toolAliasOf" => "linear_issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert Enum.any?(Inventory.typed_tools(context), &match?(%ResolvedTool{tool: "linear_issue_snapshot_alias"}, &1))
    refute Enum.any?(Inventory.authoritative_typed_tools(context), &(&1.tool == "linear_issue_snapshot_alias"))

    inventory = Inventory.render(context)

    assert inventory =~ "`linear_issue_snapshot`"
    refute inventory =~ "linear_issue_snapshot_alias"
  end

  test "resolves required capabilities from canonical tools and ignores aliases for authority" do
    context =
      tool_context()
      |> add_tool("linear_issue_snapshot_alias", %{
        "capability" => "tracker.issue_snapshot",
        "toolAliasOf" => "linear_issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:ok, [%{tool: "linear_issue_snapshot"}]} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"])
  end

  test "does not let an alias-only tool satisfy a required capability" do
    context =
      raw_only_tool_context()
      |> add_tool("linear_issue_snapshot_alias", %{
        "capability" => "tracker.issue_snapshot",
        "toolAliasOf" => "linear_issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.issue_snapshot"}} =
             Inventory.resolve_required(context, ["tracker.issue_snapshot"])
  end

  test "resolved tools reject atom values instead of coercing them to strings" do
    attrs = [
      capability: "tracker.issue_snapshot",
      tool: "linear_issue_snapshot",
      side_effect: "read_only",
      schema_version: "1",
      source_kind: "linear",
      alias_of: nil
    ]

    for field <- [:capability, :tool, :side_effect, :schema_version, :source_kind, :alias_of] do
      assert :error = attrs |> Keyword.put(field, :atom_value) |> ResolvedTool.new()
    end
  end

  test "does not let invalid side-effect metadata satisfy a required capability" do
    invalid_side_effect =
      raw_only_tool_context()
      |> add_tool("legacy_issue_snapshot", %{
        "capability" => "tracker.issue_snapshot",
        "sideEffect" => "readonly",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.issue_snapshot"}} =
             Inventory.resolve_required(invalid_side_effect, ["tracker.issue_snapshot"])

    missing_side_effect =
      raw_only_tool_context()
      |> add_tool("missing_side_effect_snapshot", %{
        "capability" => "tracker.issue_snapshot",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.issue_snapshot"}} =
             Inventory.resolve_required(missing_side_effect, ["tracker.issue_snapshot"])
  end

  test "does not hide ambiguous typed tool mappings" do
    ambiguous =
      tool_context()
      |> add_tool("second_snapshot", %{
        "capability" => "tracker.issue_snapshot",
        "sideEffect" => "read_only",
        "sourceKind" => "linear",
        "schemaVersion" => "1"
      })

    assert {:error,
            %ResolutionError{
              reason: :ambiguous_typed_tool,
              capability: "tracker.issue_snapshot",
              tools: ["linear_issue_snapshot", "second_snapshot"]
            }} =
             Inventory.resolve_required(ambiguous, ["tracker.issue_snapshot"])
  end

  test "renders an agent-facing inventory with exact runtime tool names" do
    inventory = Inventory.render(tool_context())

    assert inventory =~ "## Typed Tool Inventory"
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
    callable_name = RenderOptions.provider_callable_name(opts)

    assert %RenderOptions{} = opts
    assert is_function(callable_name, 1)
    assert callable_name.("repo_checkout") == "mcp__symphony-planned-tools__repo_checkout"
    assert RenderOptions.provider_callable_label(opts) == "Claude Code MCP tool"
  end

  test "Codex provider adapter supplies MCP inventory callable naming" do
    inventory = Inventory.render(tool_context(), ToolInventory.render_opts("codex"))
    opts = ToolInventory.render_opts("codex")
    callable_name = RenderOptions.provider_callable_name(opts)

    assert inventory =~ "`mcp__symphony-planned-tools__linear_issue_snapshot`"
    assert inventory =~ "Codex exposes Symphony Dynamic Tools through the runtime MCP bridge"
    assert %RenderOptions{} = opts
    assert is_function(callable_name, 1)
    assert callable_name.("repo_checkout") == "mcp__symphony-planned-tools__repo_checkout"
    assert RenderOptions.provider_callable_label(opts) == "Codex MCP tool"
  end

  test "CodeBuddy Code provider adapter supplies MCP inventory callable naming" do
    inventory = Inventory.render(tool_context(), ToolInventory.render_opts("codebuddy_code"))
    opts = ToolInventory.render_opts("codebuddy_code")
    callable_name = RenderOptions.provider_callable_name(opts)

    assert inventory =~ "`mcp__symphony_dynamic_tools__linear_issue_snapshot`"
    assert inventory =~ "CodeBuddy Code exposes Symphony Dynamic Tools through a session-scoped MCP server"
    assert %RenderOptions{} = opts
    assert is_function(callable_name, 1)
    assert callable_name.("repo_checkout") == "mcp__symphony_dynamic_tools__repo_checkout"
    assert RenderOptions.provider_callable_label(opts) == "CodeBuddy MCP tool"
  end

  test "renders markdown table cells through bounded escaping" do
    context =
      tool_context()
      |> put_in(["tool_metadata", "linear_issue_snapshot", "capability"], "tracker|issue`danger\nsnapshot")
      |> put_in(["tool_metadata", "linear_issue_snapshot", "sourceKind"], "linear|provider`x\nsource")

    opts = [
      {RenderOptions.provider_callable_name_key(), fn _tool -> "mcp|tool`name\nnext" end},
      {RenderOptions.provider_callable_label_key(), "Provider | Label\nName"},
      {RenderOptions.provider_callable_note_key(), "Provider\nnote\ttext"}
    ]

    inventory = Inventory.render(context, opts)

    assert inventory =~ "Provider \\| Label Name"
    assert inventory =~ "Provider note text"
    assert inventory =~ "`tracker\\|issue'danger snapshot`"
    assert inventory =~ "`mcp\\|tool'name next`"
    assert inventory =~ "`linear\\|provider'x source`"
  end

  test "raw provider tools do not satisfy typed capabilities" do
    assert {:error, %ResolutionError{reason: :missing_typed_tool, capability: "tracker.issue_snapshot"}} =
             Inventory.resolve_required(raw_only_tool_context(), ["tracker.issue_snapshot"])
  end

  test "fails closed on invalid required capability entries" do
    assert {:error, %ResolutionError{reason: :invalid_required_capability, value: nil}} =
             Inventory.resolve_required(tool_context(), ["tracker.issue_snapshot", nil])

    assert {:error, %ResolutionError{reason: :invalid_required_capability, value: ""}} =
             Inventory.resolve_required(tool_context(), [""])
  end

  test "recognizes repo-provider review comment capabilities as typed tools" do
    assert Inventory.typed_capability?("repo.add_change_proposal_comment")
    assert Inventory.typed_capability?("repo.reply_change_proposal_review_comment")
  end

  test "recognizes TAPD typed tracker capabilities as typed tools" do
    assert Inventory.typed_capability?("tracker.create_follow_up_issue")
    assert Inventory.typed_capability?("tracker.read_issue_relations")
    assert Inventory.typed_capability?("tracker.add_issue_relation")
    assert Inventory.typed_capability?("tracker.read_issue_dependencies")
    assert Inventory.typed_capability?("tracker.save_issue_dependency")
  end

  defp tool_context do
    %{
      "tool_specs" => [
        %{
          "name" => "linear_issue_snapshot",
          "description" => "Read issue snapshot.",
          "inputSchema" => %{"type" => "object"}
        },
        %{
          "name" => "legacy_tracker_api",
          "description" => "Raw tracker API.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      "tool_metadata" => %{
        "linear_issue_snapshot" => %{
          "capability" => "tracker.issue_snapshot",
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
      "tool_specs" => [
        %{
          "name" => "legacy_tracker_api",
          "description" => "Raw tracker API.",
          "inputSchema" => %{"type" => "object"}
        }
      ],
      "tool_metadata" => %{
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
    |> update_in(["tool_specs"], &(&1 ++ [%{"name" => tool_name, "inputSchema" => %{"type" => "object"}}]))
    |> put_in(["tool_metadata", tool_name], metadata)
  end
end
