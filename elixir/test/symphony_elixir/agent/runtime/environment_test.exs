defmodule SymphonyElixir.Agent.Runtime.EnvironmentTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Agent.Runtime.Environment

  test "telemetry_env/3 builds provider process telemetry environment" do
    env =
      Environment.telemetry_env(
        "claude_code",
        %{
          enabled: true,
          include_metrics: false,
          include_traces: true,
          include_logs: true,
          log_user_prompts: true,
          otlp_endpoint: "http://otel.example",
          resource_attributes: %{
            deployment: "test",
            empty: "",
            number: 42
          }
        },
        run_id: "run-1",
        issue_id: "issue-1",
        session_id: "session-1"
      )

    assert env["OTEL_TRACES_EXPORTER"] == "otlp"
    refute Map.has_key?(env, "OTEL_METRICS_EXPORTER")
    assert env["OTEL_LOGS_EXPORTER"] == "otlp"
    assert env["OTEL_LOG_USER_PROMPTS"] == "1"
    assert env["OTEL_EXPORTER_OTLP_ENDPOINT"] == "http://otel.example"
    assert env["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1"
    assert env["CLAUDE_CODE_ENHANCED_TELEMETRY_BETA"] == "1"
    assert env["OTEL_RESOURCE_ATTRIBUTES"] =~ "agent.provider=claude_code"
    assert env["OTEL_RESOURCE_ATTRIBUTES"] =~ "deployment=test"
    assert env["OTEL_RESOURCE_ATTRIBUTES"] =~ "issue.id=issue-1"
    assert env["OTEL_RESOURCE_ATTRIBUTES"] =~ "number=42"
    refute env["OTEL_RESOURCE_ATTRIBUTES"] =~ "empty="
  end

  test "current_env/3 composes dynamic tool source environment with telemetry" do
    assert {:ok, env} =
             Environment.current_env(
               "opencode",
               %{enabled: true, include_metrics: true},
               run_id: "run-env"
             )

    assert env["SYMPHONY_LINEAR_API_KEY"] == "token"
    assert env["SYMPHONY_LINEAR_ENDPOINT"] == "https://api.linear.app/graphql"
    assert env["OTEL_METRICS_EXPORTER"] == "otlp"
  end

  test "current_env/3 can skip dynamic tool source environment" do
    assert {:ok, env} =
             Environment.current_env(
               "codex",
               %{},
               include_dynamic_tool_env: false,
               agent_credential_material: SymphonyElixir.Agent.Credential.Material.new(env: %{"CODEX_MANAGED_TOKEN" => "managed-secret"})
             )

    assert env["CODEX_MANAGED_TOKEN"] == "managed-secret"
    refute Map.has_key?(env, "SYMPHONY_LINEAR_API_KEY")
  end

  test "validate_telemetry/1 rejects unsupported options" do
    assert {:error, "contains unsupported options custom"} =
             Environment.validate_telemetry(%{enabled: true, custom: true})
  end
end
