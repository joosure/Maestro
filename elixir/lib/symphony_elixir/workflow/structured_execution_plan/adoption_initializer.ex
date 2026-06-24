defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer do
  @moduledoc """
  Unified workflow adoption entry for structured execution plans.

  This module is an orchestration boundary. It resolves the workflow profile,
  checks the structured-plan adoption gate, asks the profile-owned adoption
  module to build a canonical plan, and persists it through the Store.

  It does not own profile DAGs, provider payload parsing, route policy, or
  readiness decisions.
  """

  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Context
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Request
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Result
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store

  @type result ::
          {:ok, %{status: :created, plan: map(), snapshot: map()}}
          | {:ok, %{status: :skipped, reason: :gate_disabled | :profile_not_adopted, profile: map() | nil}}
          | {:error, map()}

  @spec create_for_issue(map() | nil, map(), keyword()) :: result()
  def create_for_issue(workflow_settings, issue, opts \\ [])
      when (is_map(workflow_settings) or is_nil(workflow_settings)) and is_map(issue) and is_list(opts) do
    workflow_settings
    |> RequestBuilder.build(issue, opts)
    |> create()
  end

  @spec create(Request.t()) :: result()
  def create(%Request{} = request) do
    if request.enabled? do
      with {:ok, resolved_profile} <- resolve_profile(request),
           {:ok, adoption_module} <- adoption_module(resolved_profile),
           {:ok, attrs} <- Context.build_attrs(request, resolved_profile),
           {:ok, plan} <- adoption_module.build(attrs),
           {:ok, created_plan} <- Store.create(plan, request.store_opts) do
        Result.created(created_plan)
      else
        {:skip, reason, profile} ->
          Result.skipped(reason, profile)

        {:error, _reason} = error ->
          error
      end
    else
      Result.skipped(:gate_disabled, nil)
    end
  end

  @spec enabled?(map() | nil) :: boolean()
  defdelegate enabled?(workflow_settings), to: RequestBuilder

  defp resolve_profile(%Request{} = request) do
    request.registry_profile_config
    |> ProfileRegistry.resolve()
    |> case do
      {:ok, resolved_profile} ->
        {:ok, resolved_profile}

      {:error, reason} ->
        Result.profile_resolution_failed(reason)
    end
  end

  defp adoption_module(resolved_profile) do
    profile_module = resolved_profile.module

    if function_exported?(profile_module, :structured_execution_plan_adoption, 0) do
      case profile_module.structured_execution_plan_adoption() do
        module when is_atom(module) and not is_nil(module) ->
          if adoption_builder?(module) do
            {:ok, module}
          else
            Result.invalid_adoption_module(module)
          end

        _value ->
          {:skip, :profile_not_adopted, Result.profile_snapshot(resolved_profile)}
      end
    else
      {:skip, :profile_not_adopted, Result.profile_snapshot(resolved_profile)}
    end
  end

  defp adoption_builder?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> function_exported?(module, :build, 1)
      {:error, _reason} -> false
    end
  end
end
