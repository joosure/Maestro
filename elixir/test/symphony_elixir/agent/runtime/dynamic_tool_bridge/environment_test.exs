defmodule SymphonyElixir.Agent.Runtime.DynamicToolBridge.EnvironmentTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.Runtime.DynamicToolBridge.Environment

  test "context_env/1 returns captured dynamic tool source environment" do
    assert %{"DYNAMIC_TOOL_ENV" => "enabled"} =
             Environment.context_env(%{
               tool_environment: %{"DYNAMIC_TOOL_ENV" => "enabled"}
             })
  end

  test "context_env/1 defaults missing environment to an empty map" do
    assert Environment.context_env(%{}) == %{}
  end
end
