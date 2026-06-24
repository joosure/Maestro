defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.ProviderSessionEvent.Values do
  @moduledoc """
  Canonical provider-session event enum values and aliases.
  """

  alias SymphonyElixir.Agent.ExecutionPlan.Contract, as: AgentContract

  @authority "non_authoritative"
  @default_trust_class AgentContract.agent_declared_trust_class()
  @agent_requested_trust_class "agent_requested"

  @agent_visible_plan_surface "agent_visible_plan"
  @provider_session_tasks_surface "provider_session_tasks"
  @hook_observation_surface "hook_observation"
  @canonical_execution_plan_proposal_surface "canonical_execution_plan_proposal"
  @surfaces [
    @agent_visible_plan_surface,
    @provider_session_tasks_surface,
    @hook_observation_surface,
    @canonical_execution_plan_proposal_surface
  ]

  @surface_alias_by_name %{
    "plan" => @agent_visible_plan_surface,
    "agent_plan" => @agent_visible_plan_surface,
    "todos" => @provider_session_tasks_surface,
    "todo" => @provider_session_tasks_surface,
    "tasks" => @provider_session_tasks_surface,
    "hook" => @hook_observation_surface,
    "hooks" => @hook_observation_surface
  }

  @trust_class_by_name %{
    @agent_requested_trust_class => @agent_requested_trust_class
  }

  @complete_status "complete"
  @pending_status "pending"
  @in_progress_status "in_progress"
  @blocked_status "blocked"
  @failed_status "failed"
  @skipped_status "skipped"
  @unknown_status "unknown"

  @task_status_by_name [
                         {~w(complete completed done success succeeded passed pass), @complete_status},
                         {~w(pending todo open queued planned), @pending_status},
                         {~w(in_progress running started active doing), @in_progress_status},
                         {[@blocked_status], @blocked_status},
                         {~w(failed failure error), @failed_status},
                         {~w(skipped skip cancelled canceled), @skipped_status}
                       ]
                       |> Enum.flat_map(fn {aliases, status} -> Enum.map(aliases, &{&1, status}) end)
                       |> Map.new()

  @status_non_authoritative_warning "provider_native_status_non_authoritative"
  @complete_does_not_satisfy_evidence_warning "provider_native_complete_does_not_satisfy_evidence"

  @spec authority() :: String.t()
  def authority, do: @authority

  @spec default_trust_class() :: String.t()
  def default_trust_class, do: @default_trust_class

  @spec surfaces() :: [String.t()]
  def surfaces, do: @surfaces

  @spec provider_session_tasks_surface() :: String.t()
  def provider_session_tasks_surface, do: @provider_session_tasks_surface

  @spec hook_observation_surface() :: String.t()
  def hook_observation_surface, do: @hook_observation_surface

  @spec complete_status() :: String.t()
  def complete_status, do: @complete_status

  @spec unknown_status() :: String.t()
  def unknown_status, do: @unknown_status

  @spec normalize_surface(String.t() | nil) :: String.t() | nil
  def normalize_surface(nil), do: nil

  def normalize_surface(surface) when is_binary(surface) do
    normalized = normalize_name(surface)

    cond do
      normalized in @surfaces -> normalized
      true -> Map.get(@surface_alias_by_name, normalized, normalized)
    end
  end

  @spec normalize_trust_class(String.t() | nil) :: String.t()
  def normalize_trust_class(value) when is_binary(value), do: Map.get(@trust_class_by_name, value, @default_trust_class)
  def normalize_trust_class(_value), do: @default_trust_class

  @spec normalize_status(String.t() | nil) :: String.t()
  def normalize_status(nil), do: @unknown_status

  def normalize_status(status) when is_binary(status) do
    status
    |> normalize_name()
    |> then(&Map.get(@task_status_by_name, &1, @unknown_status))
  end

  def normalize_status(_status), do: @unknown_status

  @spec warnings(boolean()) :: [String.t()]
  def warnings(completed_task?) do
    base = [@status_non_authoritative_warning]

    if completed_task? do
      [@complete_does_not_satisfy_evidence_warning | base]
    else
      base
    end
    |> Enum.uniq()
  end

  @spec complete_does_not_satisfy_evidence_warning() :: String.t()
  def complete_does_not_satisfy_evidence_warning, do: @complete_does_not_satisfy_evidence_warning

  defp normalize_name(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end
end
