defmodule SymphonyElixir.Release.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.Release.RuntimeConfig
  alias SymphonyElixir.Release.WorkflowSource
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.TemplateRegistry

  test "exposes the release runtime environment contract" do
    assert RuntimeConfig.host_env() == "HOST"
    assert RuntimeConfig.port_env() == "PORT"
    assert RuntimeConfig.default_host() == "0.0.0.0"
    assert RuntimeConfig.default_port() == "4000"
  end

  test "loads host, port, and workflow source from environment" do
    config =
      RuntimeConfig.from_env(%{
        RuntimeConfig.host_env() => " 127.0.0.1 ",
        RuntimeConfig.port_env() => " 4100 ",
        WorkflowSource.workflow_path_env() => " /app/WORKFLOW.local.md ",
        WorkflowSource.template_env() => linear_github_opencode_template_alias()
      })

    assert config.host == "127.0.0.1"
    assert config.port == "4100"
    assert config.workflow_source == {:workflow_path, "/app/WORKFLOW.local.md"}
  end

  test "uses safe defaults when optional environment is missing" do
    assert RuntimeConfig.from_env(%{}) == %RuntimeConfig{
             host: RuntimeConfig.default_host(),
             port: RuntimeConfig.default_port(),
             workflow_source: {:template, WorkflowSource.default_template()}
           }
  end

  defp linear_github_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.opencode()
    )
  end
end
