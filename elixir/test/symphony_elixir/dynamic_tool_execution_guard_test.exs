defmodule SymphonyElixir.DynamicToolExecutionGuardTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.DynamicTool.Context
  alias SymphonyElixir.Agent.DynamicTool.EventContract
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard
  alias SymphonyElixir.Agent.DynamicTool.ExecutionGuard.{Contract, Decision, ErrorPayload}
  alias SymphonyElixir.Agent.DynamicTool.Metadata

  test "returns a structured decision instead of a raw response payload" do
    context =
      context_with_tool(%{
        "name" => "raw_probe",
        "sideEffect" => "read_only"
      })

    assert {:error, %Decision{} = decision} =
             ExecutionGuard.ensure_authoritative_typed_tool(context, "raw_probe")

    assert decision.code == EventContract.untyped_tool()
    assert decision.message == Contract.untyped_tool_message()
    assert decision.details == %{Contract.tool_key() => "raw_probe"}
    refute Map.has_key?(decision, "error")

    assert %{
             "error" => %{
               "code" => "untyped_dynamic_tool",
               "message" => "Dynamic tool execution requires a canonical typed tool capability.",
               "tool" => "raw_probe"
             }
           } = ErrorPayload.from_decision(decision)
  end

  test "uses metadata contract key for alias rejection details" do
    context =
      context_with_tool(%{
        "name" => "provider_alias",
        "capability" => "test.alias",
        "sideEffect" => "read_only",
        "toolAliasOf" => "canonical_probe"
      })

    assert {:error, %Decision{} = decision} =
             ExecutionGuard.ensure_authoritative_typed_tool(context, "provider_alias")

    assert decision.code == EventContract.alias_tool()
    assert decision.details[Contract.tool_key()] == "provider_alias"
    assert decision.details[Metadata.Contract.tool_alias_of()] == "canonical_probe"
    refute Map.has_key?(decision.details, "aliasOf")
  end

  test "normalizes side-effect validation details through guard contract" do
    context =
      context_with_tool(%{
        "name" => "legacy_probe",
        "capability" => "test.legacy",
        "sideEffect" => "readonly"
      })

    assert {:error, %Decision{} = decision} =
             ExecutionGuard.ensure_authoritative_typed_tool(context, "legacy_probe")

    assert decision.code == EventContract.invalid_tool_metadata()

    assert decision.details == %{
             Contract.tool_key() => "legacy_probe",
             Contract.field_key() => Metadata.Contract.side_effect(),
             Contract.reason_key() => Contract.reason_invalid(),
             Contract.value_key() => "readonly",
             Contract.allowed_values_key() => Metadata.Contract.side_effect_classes()
           }
  end

  defp context_with_tool(tool_spec) when is_map(tool_spec) do
    tool_spec =
      tool_spec
      |> Map.put_new("description", "Probe tool.")
      |> Map.put_new("inputSchema", %{"type" => "object"})

    Context.from_opts(tool_context: %{"tool_specs" => [tool_spec]})
  end
end
