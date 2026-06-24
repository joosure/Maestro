defmodule SymphonyElixir.Release.RunnerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.Release.Runner
  alias SymphonyElixir.Release.RuntimeConfig
  alias SymphonyElixir.Release.WorkflowSource
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.Template, as: TemplateRegistry
  @ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  test "builds template serve args from environment" do
    template_alias = linear_github_opencode_template_alias()

    args =
      Runner.serve_args_from_env(%{
        WorkflowSource.template_env() => template_alias,
        RuntimeConfig.host_env() => "0.0.0.0",
        RuntimeConfig.port_env() => "4000"
      })

    assert args == [
             @ack_flag,
             "--host",
             "0.0.0.0",
             "--port",
             "4000",
             "--template",
             template_alias
           ]
  end

  test "prefers workflow path over template when provided" do
    args =
      Runner.serve_args_from_env(%{
        WorkflowSource.workflow_path_env() => "/app/WORKFLOW.local.md",
        WorkflowSource.template_env() => linear_github_opencode_template_alias(),
        RuntimeConfig.host_env() => "127.0.0.1",
        RuntimeConfig.port_env() => "4100"
      })

    assert args == [
             @ack_flag,
             "--host",
             "127.0.0.1",
             "--port",
             "4100",
             "/app/WORKFLOW.local.md"
           ]
  end

  test "trims environment values before building serve args" do
    args =
      Runner.serve_args_from_env(%{
        WorkflowSource.workflow_path_env() => " /app/WORKFLOW.local.md ",
        RuntimeConfig.host_env() => " 127.0.0.1 ",
        RuntimeConfig.port_env() => " 4100 "
      })

    assert args == [
             @ack_flag,
             "--host",
             "127.0.0.1",
             "--port",
             "4100",
             "/app/WORKFLOW.local.md"
           ]
  end

  test "uses safe defaults when optional environment is missing" do
    args = Runner.serve_args_from_env(%{})

    assert args == [
             @ack_flag,
             "--host",
             RuntimeConfig.default_host(),
             "--port",
             RuntimeConfig.default_port(),
             "--template",
             WorkflowSource.default_template()
           ]
  end

  defp linear_github_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.opencode()
    )
  end
end
