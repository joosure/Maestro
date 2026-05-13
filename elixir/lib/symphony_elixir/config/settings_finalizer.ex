defmodule SymphonyElixir.Config.SettingsFinalizer do
  @moduledoc false

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Config.{InputNormalizer, RepoProviderSettingsFinalizer, TrackerSettingsFinalizer}
  alias SymphonyElixir.Config.Schema.Credentials, as: CredentialSchema
  alias SymphonyElixir.Workflow.ProfileRegistry

  @spec normalize_input(map()) :: map()
  def normalize_input(config) when is_map(config) do
    InputNormalizer.normalize_input(config)
  end

  @spec finalize_settings(struct()) :: struct()
  def finalize_settings(settings) do
    workspace = %{
      settings.workspace
      | root:
          InputNormalizer.resolve_path_value(
            settings.workspace.root,
            Path.join(System.tmp_dir!(), "symphony_workspaces")
          ),
        bootstrap_automation_from: InputNormalizer.resolve_local_path_setting(settings.workspace.bootstrap_automation_from)
    }

    workflow = finalize_workflow(settings.workflow)
    agent = finalize_agent(settings.agent)
    agent_provider = finalize_agent_provider(settings.agent_provider)

    %{
      settings
      | workflow: workflow,
        tracker: TrackerSettingsFinalizer.finalize(settings.tracker, workflow),
        repo: RepoProviderSettingsFinalizer.finalize(settings.repo),
        workspace: workspace,
        agent: agent,
        agent_provider: agent_provider
    }
  end

  defp finalize_workflow(workflow) when is_map(workflow) do
    profile =
      workflow
      |> Map.get(:profile, %{})
      |> ProfileRegistry.normalize_config()

    %{workflow | profile: profile}
  end

  defp finalize_workflow(nil) do
    %SymphonyElixir.Config.Schema.Workflow{profile: ProfileRegistry.default_profile_config()}
  end

  defp finalize_agent_provider(provider) do
    kind = InputNormalizer.resolve_string_setting(provider.kind, AgentProvider.default_kind())
    options = InputNormalizer.normalize_optional_map(provider.options) || %{}

    %{
      provider
      | kind: kind,
        options: AgentProvider.finalize_options(kind, options)
    }
  end

  defp finalize_agent(agent) do
    %{agent | credentials: finalize_agent_credentials(agent.credentials)}
  end

  defp finalize_agent_credentials(credentials) do
    %{
      credentials
      | store_root:
          InputNormalizer.resolve_path_value(
            credentials.store_root,
            CredentialSchema.default_store_root()
          )
    }
  end
end
