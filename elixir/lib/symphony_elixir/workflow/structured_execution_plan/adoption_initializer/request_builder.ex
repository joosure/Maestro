defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder do
  @moduledoc """
  Raw boundary for workflow structured-plan adoption initialization.

  This module converts external workflow settings, issue maps, and runtime opts
  into `AdoptionInitializer.Request`. It is the only adoption initializer module
  that should read raw atom/string keyed maps.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.Request
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder.RawInput
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Fields
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Store.Options, as: StoreOptions

  @plan_id_key Fields.plan_id()
  @run_id_key Fields.run_id()
  @issue_id_key Fields.issue_id()
  @issue_identifier_key Fields.issue_identifier()
  @tracker_kind_key Fields.tracker_kind()
  @route_key_key Fields.route_key()
  @status_key Fields.status()
  @created_at_key Fields.created_at()
  @updated_at_key Fields.updated_at()

  @spec build(map() | nil, map(), keyword()) :: Request.t()
  def build(workflow_settings, issue, opts \\ [])
      when (is_map(workflow_settings) or is_nil(workflow_settings)) and is_map(issue) and is_list(opts) do
    workflow_settings = workflow_settings || %{}

    %Request{
      enabled?: enabled?(workflow_settings),
      registry_profile_config: registry_profile_config(workflow_settings),
      issue_context: issue_context(issue),
      run_context: run_context(workflow_settings, issue, opts),
      tracker_context: tracker_context(workflow_settings, issue, opts),
      store_opts: StoreOptions.from_adoption_initializer(opts)
    }
  end

  @spec enabled?(map() | nil) :: boolean()
  def enabled?(workflow_settings) when is_map(workflow_settings) do
    workflow_settings
    |> workflow_profile_options()
    |> RawInput.map_value(RawInput.structured_execution_plan_key())
    |> case do
      true ->
        true

      %{} = structured_execution_plan ->
        RawInput.map_value(structured_execution_plan, RawInput.enabled_key()) == true

      _value ->
        false
    end
  end

  def enabled?(_workflow_settings), do: false

  @spec registry_profile_config(map() | nil) :: map()
  def registry_profile_config(workflow_settings) when is_map(workflow_settings) do
    workflow_settings
    |> workflow_profile_config()
    |> strip_adoption_gate()
  end

  def registry_profile_config(_workflow_settings), do: %{}

  @spec workflow_profile_options(map() | nil) :: map()
  def workflow_profile_options(workflow_settings) when is_map(workflow_settings) do
    workflow_settings
    |> workflow_profile_config()
    |> RawInput.map_value(RawInput.options_key())
    |> RawInput.normalize_map()
  end

  def workflow_profile_options(_workflow_settings), do: %{}

  defp workflow_profile_config(workflow_settings) do
    workflow_settings
    |> RawInput.map_value(RawInput.workflow_key())
    |> RawInput.map_value(RawInput.profile_key())
    |> RawInput.normalize_map()
  end

  defp strip_adoption_gate(profile_config) when is_map(profile_config) do
    case RawInput.map_value(profile_config, RawInput.options_key()) do
      %{} = options ->
        RawInput.put_key(
          profile_config,
          RawInput.options_key(),
          RawInput.delete_key(options, RawInput.structured_execution_plan_key())
        )

      _value ->
        profile_config
    end
  end

  defp issue_context(issue) do
    %{
      issue_id: RawInput.map_value(issue, @issue_id_key) || RawInput.map_value(issue, RawInput.id_key()),
      issue_identifier: RawInput.map_value(issue, @issue_identifier_key) || RawInput.map_value(issue, RawInput.identifier_key())
    }
  end

  defp run_context(workflow_settings, issue, opts) do
    %{
      plan_id: first_value(opts, issue, workflow_settings, @plan_id_key),
      run_id: first_value(opts, issue, workflow_settings, @run_id_key),
      route_key: first_value(opts, issue, workflow_settings, @route_key_key),
      status: first_value(opts, issue, workflow_settings, @status_key),
      created_at: first_value(opts, issue, workflow_settings, @created_at_key),
      updated_at: first_value(opts, issue, workflow_settings, @updated_at_key)
    }
  end

  defp tracker_context(workflow_settings, issue, opts) do
    %{
      tracker_kind: first_value(opts, issue, workflow_settings, @tracker_kind_key) || tracker_kind(workflow_settings)
    }
  end

  defp first_value(opts, issue, workflow_settings, key) do
    RawInput.keyword_value(opts, key) ||
      RawInput.map_value(issue, key) ||
      workflow_value(workflow_settings, key)
  end

  defp tracker_kind(workflow_settings) do
    workflow_settings
    |> RawInput.map_value(RawInput.tracker_key())
    |> RawInput.map_value(RawInput.kind_key())
  end

  defp workflow_value(workflow_settings, key) do
    workflow_settings
    |> RawInput.map_value(RawInput.workflow_key())
    |> RawInput.map_value(key)
  end
end
