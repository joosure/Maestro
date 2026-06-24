defmodule SymphonyElixir.Release.WorkflowSource do
  @moduledoc false

  alias SymphonyElixir.Platform.Env
  alias SymphonyElixir.Workflow.Template, as: TemplateRegistry
  @workflow_path_env "SYMPHONY_WORKFLOW_PATH"
  @template_env "SYMPHONY_TEMPLATE"

  @type t :: {:workflow_path, String.t()} | {:template, String.t()}

  @spec workflow_path_env() :: String.t()
  def workflow_path_env, do: @workflow_path_env

  @spec template_env() :: String.t()
  def template_env, do: @template_env

  @spec default_template() :: String.t()
  def default_template, do: TemplateRegistry.local_quickstart_alias()

  @spec from_env(map()) :: t()
  def from_env(env_map) when is_map(env_map) do
    case Env.value(env_map, @workflow_path_env) do
      nil -> {:template, Env.value(env_map, @template_env, default_template())}
      workflow_path -> {:workflow_path, workflow_path}
    end
  end
end
