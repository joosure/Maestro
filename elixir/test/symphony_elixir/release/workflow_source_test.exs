defmodule SymphonyElixir.Release.WorkflowSourceTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.AgentProvider.Kinds, as: AgentProviderKinds
  alias SymphonyElixir.Release.WorkflowSource
  alias SymphonyElixir.RepoProvider.Kinds, as: RepoProviderKinds
  alias SymphonyElixir.Tracker.Kinds, as: TrackerKinds
  alias SymphonyElixir.Workflow.TemplateRegistry

  test "exposes the workflow source environment contract" do
    assert WorkflowSource.workflow_path_env() == "SYMPHONY_WORKFLOW_PATH"
    assert WorkflowSource.template_env() == "SYMPHONY_TEMPLATE"
    assert WorkflowSource.default_template() == TemplateRegistry.local_quickstart_alias()
  end

  test "uses explicit workflow path before template" do
    assert WorkflowSource.from_env(%{
             WorkflowSource.workflow_path_env() => " /app/WORKFLOW.local.md ",
             WorkflowSource.template_env() => linear_github_opencode_template_alias()
           }) == {:workflow_path, "/app/WORKFLOW.local.md"}
  end

  test "uses configured template when workflow path is missing" do
    template_alias = linear_github_codex_template_alias()

    assert WorkflowSource.from_env(%{WorkflowSource.template_env() => " #{template_alias} "}) ==
             {:template, template_alias}
  end

  test "uses mock template when no workflow source is configured" do
    assert WorkflowSource.from_env(%{}) == {:template, WorkflowSource.default_template()}
  end

  defp linear_github_opencode_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.opencode()
    )
  end

  defp linear_github_codex_template_alias do
    TemplateRegistry.alias_for!(
      TrackerKinds.linear(),
      RepoProviderKinds.github(),
      AgentProviderKinds.codex()
    )
  end
end
