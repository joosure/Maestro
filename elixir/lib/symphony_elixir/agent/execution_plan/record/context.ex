defmodule SymphonyElixir.Agent.ExecutionPlan.Record.Context do
  @moduledoc false

  alias SymphonyElixir.Agent.ExecutionPlan.Fields
  alias SymphonyElixir.Agent.ExecutionPlan.Record.Extensions
  alias SymphonyElixir.Agent.ExecutionPlan.Record.RepoRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.TrackerRef
  alias SymphonyElixir.Agent.ExecutionPlan.Record.WorkflowRef

  @type t :: %__MODULE__{
          context_kind: String.t(),
          tenant_id: String.t() | nil,
          workspace_id: String.t(),
          run_id: String.t(),
          agent_session_id: String.t() | nil,
          task_id: String.t() | nil,
          recipe_run_id: String.t() | nil,
          workflow_ref: WorkflowRef.t() | nil,
          repo_ref: RepoRef.t() | nil,
          tracker_ref: TrackerRef.t() | nil,
          policy_refs: [String.t()] | nil,
          source: String.t(),
          mode: String.t(),
          extensions: Extensions.t() | nil
        }

  defstruct context_kind: nil,
            tenant_id: nil,
            workspace_id: nil,
            run_id: nil,
            agent_session_id: nil,
            task_id: nil,
            recipe_run_id: nil,
            workflow_ref: nil,
            repo_ref: nil,
            tracker_ref: nil,
            policy_refs: nil,
            source: nil,
            mode: nil,
            extensions: nil

  @spec from_map(map()) :: t()
  def from_map(context) when is_map(context) do
    %__MODULE__{
      context_kind: Map.fetch!(context, Fields.context_kind()),
      tenant_id: Map.get(context, Fields.tenant_id()),
      workspace_id: Map.fetch!(context, Fields.workspace_id()),
      run_id: Map.fetch!(context, Fields.run_id()),
      agent_session_id: Map.get(context, Fields.agent_session_id()),
      task_id: Map.get(context, Fields.task_id()),
      recipe_run_id: Map.get(context, Fields.recipe_run_id()),
      workflow_ref: WorkflowRef.from_map(Map.get(context, Fields.workflow_ref())),
      repo_ref: RepoRef.from_map(Map.get(context, Fields.repo_ref())),
      tracker_ref: TrackerRef.from_map(Map.get(context, Fields.tracker_ref())),
      policy_refs: Map.get(context, Fields.policy_refs()),
      source: Map.fetch!(context, Fields.source()),
      mode: Map.fetch!(context, Fields.mode()),
      extensions: Extensions.from_map(Map.get(context, Fields.extensions()))
    }
  end
end
