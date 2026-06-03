defmodule SymphonyElixir.Config.Schema do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Config.{ErrorFormatter, SandboxPolicy, SettingsFinalizer}

  alias __MODULE__.{
    Agent,
    AgentProvider,
    Hooks,
    Observability,
    Polling,
    Repo,
    Runtime,
    Server,
    Tracker,
    Workflow,
    Worker,
    Workspace
  }

  alias SymphonyElixir.Workflow.Lifecycle, as: WorkflowLifecycle

  @primary_key false

  @type t :: %__MODULE__{}

  embedded_schema do
    embeds_one(:workflow, Workflow, on_replace: :update, defaults_to_struct: true)
    embeds_one(:tracker, Tracker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:polling, Polling, on_replace: :update, defaults_to_struct: true)
    embeds_one(:workspace, Workspace, on_replace: :update, defaults_to_struct: true)
    embeds_one(:worker, Worker, on_replace: :update, defaults_to_struct: true)
    embeds_one(:runtime, Runtime, on_replace: :update, defaults_to_struct: true)
    embeds_one(:repo, Repo, on_replace: :update, defaults_to_struct: true)
    embeds_one(:agent, Agent, on_replace: :update, defaults_to_struct: true)
    embeds_one(:agent_provider, AgentProvider, on_replace: :update, defaults_to_struct: true)
    embeds_one(:hooks, Hooks, on_replace: :update, defaults_to_struct: true)
    embeds_one(:observability, Observability, on_replace: :update, defaults_to_struct: true)
    embeds_one(:server, Server, on_replace: :update, defaults_to_struct: true)
  end

  @spec parse(map()) :: {:ok, %__MODULE__{}} | {:error, {:invalid_workflow_config, String.t()}}
  def parse(config) when is_map(config) do
    config
    |> SettingsFinalizer.normalize_input()
    |> changeset()
    |> apply_action(:validate)
    |> case do
      {:ok, settings} ->
        {:ok, SettingsFinalizer.finalize_settings(settings)}

      {:error, changeset} ->
        {:error, {:invalid_workflow_config, ErrorFormatter.format(changeset)}}
    end
  end

  @spec resolve_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil) :: map()
  def resolve_turn_sandbox_policy(settings, workspace \\ nil) do
    SandboxPolicy.resolve_turn_sandbox_policy(settings, workspace)
  end

  @spec resolve_runtime_turn_sandbox_policy(%__MODULE__{}, Path.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def resolve_runtime_turn_sandbox_policy(settings, workspace \\ nil, opts \\ []) do
    SandboxPolicy.resolve_runtime_turn_sandbox_policy(settings, workspace, opts)
  end

  @spec normalize_issue_state(String.t()) :: String.t()
  def normalize_issue_state(state_name) when is_binary(state_name) do
    WorkflowLifecycle.normalize_tracker_state(state_name)
  end

  def normalize_issue_state(state_name), do: WorkflowLifecycle.normalize_tracker_state(state_name)

  defp changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [])
    |> reject_top_level_agent_subsections(attrs)
    |> cast_embed(:workflow, with: &Workflow.changeset/2)
    |> cast_embed(:tracker, with: &Tracker.changeset/2)
    |> cast_embed(:polling, with: &Polling.changeset/2)
    |> cast_embed(:workspace, with: &Workspace.changeset/2)
    |> cast_embed(:worker, with: &Worker.changeset/2)
    |> cast_embed(:runtime, with: &Runtime.changeset/2)
    |> cast_embed(:repo, with: &Repo.changeset/2)
    |> cast_embed(:agent, with: &Agent.changeset/2)
    |> cast_embed(:agent_provider, with: &AgentProvider.changeset/2)
    |> cast_embed(:hooks, with: &Hooks.changeset/2)
    |> cast_embed(:observability, with: &Observability.changeset/2)
    |> cast_embed(:server, with: &Server.changeset/2)
  end

  defp reject_top_level_agent_subsections(changeset, attrs) when is_map(attrs) do
    attrs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.reduce(changeset, fn
      "agent_policy", changeset ->
        add_error(changeset, :agent, "agent_policy must be configured as agent.execution")

      "agent_credentials", changeset ->
        add_error(changeset, :agent, "agent_credentials must be configured as agent.credentials")

      "agent_quota", changeset ->
        add_error(changeset, :agent, "agent_quota must be configured as agent.quota")

      "agent_runtime", changeset ->
        add_error(changeset, :runtime, "agent_runtime has been replaced by runtime.agent")

      _key, changeset ->
        changeset
    end)
  end
end
