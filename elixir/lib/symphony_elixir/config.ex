defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.Config.Capabilities, as: ConfigCapabilities
  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Config.TypedToolCapabilities
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.RepoProvider.Error, as: RepoProviderError
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Tracker.Error, as: TrackerError
  alias SymphonyElixir.Workflow
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities
  alias SymphonyElixir.Workflow.ChangeProposalReconciliation.Config, as: ChangeProposalReconciliationConfig
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry
  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.Prompt.Template, as: PromptTemplate

  @type agent_provider_settings :: %{
          kind: String.t(),
          options: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    config = settings!()

    Map.get(
      config.agent.execution.max_concurrent_agents_by_state,
      Schema.normalize_issue_state(state_name),
      config.agent.execution.max_concurrent_agents
    )
  end

  def max_concurrent_agents_for_state(_state_name), do: settings!().agent.execution.max_concurrent_agents

  @spec agent_provider_settings() :: agent_provider_settings()
  def agent_provider_settings do
    settings!().agent_provider
  end

  @spec agent_credentials_settings() :: map()
  def agent_credentials_settings do
    settings!().agent.credentials
  end

  @spec agent_quota_settings() :: map()
  def agent_quota_settings do
    settings!().agent.quota
  end

  @spec agent_runtime_settings() :: map()
  def agent_runtime_settings do
    settings!().agent_runtime
  end

  @spec agent_provider_options() :: map()
  def agent_provider_options do
    agent_provider_settings().options
  end

  @spec agent_provider_option(String.t()) :: term()
  def agent_provider_option(key) when is_binary(key) do
    Map.get(agent_provider_options(), key)
  end

  @spec agent_provider_kind() :: String.t()
  def agent_provider_kind do
    agent_provider_settings().kind
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} ->
        PromptTemplate.select(prompt)

      _ ->
        PromptTemplate.default_template()
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, settings} <- settings() do
      validate_semantics(settings)
    end
  end

  defp validate_semantics(settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      is_nil(Tracker.adapter_for(settings.tracker.kind)) ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      is_nil(AgentProvider.adapter_for(settings.agent_provider.kind)) ->
        {:error, {:unsupported_agent_provider_kind, settings.agent_provider.kind}}

      true ->
        with {:ok, resolved_profile} <- ProfileRegistry.resolve(settings.workflow.profile),
             :ok <- ExecutionProfileRegistry.validate_registry(),
             :ok <- Tracker.validate_config(settings.tracker),
             :ok <- AgentProvider.validate_config(settings.agent_provider),
             :ok <- RepoProvider.validate_config(settings.repo),
             :ok <- WorkflowLifecycle.validate_state_phase_map(settings.tracker),
             :ok <- ChangeProposalReconciliationConfig.validate_settings(settings, resolved_profile),
             :ok <- ExecutionProfileRegistry.validate_selected_execution_profiles(settings, resolved_profile),
             :ok <-
               WorkflowCapabilities.validate_required_capabilities(
                 settings,
                 ConfigCapabilities.available_capabilities(settings)
               ),
             :ok <- TypedToolCapabilities.validate_required(settings) do
          :ok
        end
    end
  end

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      %TrackerError{operation: :validate_config, message: message} when is_binary(message) and message != "" ->
        "Invalid WORKFLOW.md config: #{message}"

      %RepoProviderError{operation: :validate_config, message: message} when is_binary(message) and message != "" ->
        "Invalid WORKFLOW.md config: #{message}"

      {:unsupported_repo_provider_option, kind, option} ->
        RepoProviderError.unsupported_option(kind, option).message

      {:unsupported_agent_provider_kind, kind} ->
        "Unsupported agent_provider.kind: #{inspect(kind)}"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
