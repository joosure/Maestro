defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.ProviderContextTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.Options
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.ProviderContext
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Tool.Aliases, as: ToolAliases

  test "normalizes raw provider and tracker context only at the Dynamic Tool source boundary" do
    source_context = %{
      "provider_contexts" => [
        %{"provider_key" => "linear"},
        %{tracker_kind: "tapd"},
        "jira",
        %{"kind" => "linear"}
      ]
    }

    assert Options.provider_contexts(source_context) == [
             %{provider_key: "linear"},
             %{provider_key: "tapd"},
             %{provider_key: "jira"}
           ]
  end

  test "provider context contract accepts supported raw key aliases and rejects invalid keys" do
    assert ProviderContext.from_input(%{"provider_kind" => "github"}) == [%{provider_key: "github"}]
    assert ProviderContext.from_input(%{kind: :tapd}) == [%{provider_key: "tapd"}]
    assert ProviderContext.from_input(%{"provider_key" => 42}) == []
  end

  test "tool aliases consume canonical provider contexts instead of raw string-keyed maps" do
    assert {:ok, "workflow_plan_update_item"} =
             ToolAliases.canonical_name("jira_plan_update_item", [%{provider_key: "jira"}])

    assert :error == ToolAliases.canonical_name("jira_plan_update_item", [%{"provider_key" => "jira"}])
  end
end
