defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Resolver do
  @moduledoc false

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Source
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @type resolved_profile :: ProfileRegistry.resolved_profile()

  @spec effective_allowed_execution_profiles(resolved_profile()) :: [String.t()]
  def effective_allowed_execution_profiles(%{module: profile_module, options: profile_options}) do
    profile_module
    |> ProfileRegistry.allowed_execution_profiles(profile_options)
    |> Enum.uniq()
  end

  @spec resolve(resolved_profile(), String.t(), atom()) ::
          {:ok, {:profile_owned, String.t()} | {:runtime_registered, Entry.t()}} | {:error, term()}
  def resolve(%{module: profile_module, options: profile_options} = profile_context, execution_profile, action)
      when is_binary(execution_profile) do
    normalized_name = Values.normalize_name(execution_profile)
    normalized_action = RoutePolicy.normalize_action(action)
    declared_profiles = ProfileRegistry.allowed_execution_profiles(profile_module, profile_options)

    cond do
      is_nil(normalized_name) ->
        {:error, {:invalid_workflow_execution_profile, execution_profile}}

      normalized_name not in declared_profiles ->
        {:error, {:undeclared_workflow_execution_profile, normalized_name, declared_profiles}}

      true ->
        resolve_declared(profile_context, normalized_name, normalized_action)
    end
  end

  def resolve(_profile_context, execution_profile, _action),
    do: {:error, {:invalid_workflow_execution_profile, execution_profile}}

  @spec required_capabilities(resolved_profile(), String.t(), atom()) :: [String.t()]
  def required_capabilities(
        %{module: profile_module, options: profile_options} = profile_context,
        execution_profile,
        action
      ) do
    case resolve(profile_context, execution_profile, action) do
      {:ok, {:runtime_registered, %Entry{} = entry}} ->
        entry.required_capabilities

      {:ok, {:profile_owned, execution_profile}} ->
        ProfileRegistry.execution_profile_required_capabilities(profile_module, execution_profile, profile_options)

      _other ->
        []
    end
  end

  @spec matching_entries(resolved_profile()) :: [Entry.t()]
  defp matching_entries(%{kind: profile_kind, version: profile_version}) do
    case Source.fetch_entries() do
      {:ok, entries} ->
        Enum.filter(entries, fn %Entry{} = entry ->
          entry.profile_kind == profile_kind and profile_version in entry.profile_versions
        end)

      {:error, _reason} ->
        []
    end
  end

  defp resolve_declared(
         %{module: profile_module, options: profile_options} = profile_context,
         execution_profile,
         action
       ) do
    if ProfileRegistry.runtime_execution_profile_extensions_enabled?(profile_module, profile_options) do
      resolve_declared_runtime_registered(profile_context, execution_profile, action)
    else
      {:ok, {:profile_owned, execution_profile}}
    end
  end

  defp resolve_declared_runtime_registered(
         %{module: profile_module, kind: profile_kind, version: profile_version} = profile_context,
         execution_profile,
         action
       ) do
    case matching_entries(profile_context) |> Enum.find(&(&1.name == execution_profile)) do
      nil ->
        if profile_owned_execution_profile?(profile_module, execution_profile) do
          {:ok, {:profile_owned, execution_profile}}
        else
          {:error, {:missing_workflow_execution_profile_registry_entry, execution_profile, profile_kind, profile_version}}
        end

      %Entry{} = entry ->
        if action in entry.supported_actions do
          {:ok, {:runtime_registered, entry}}
        else
          {:error, {:unsupported_workflow_execution_profile_action, execution_profile, action}}
        end
    end
  end

  defp profile_owned_execution_profile?(profile_module, execution_profile) when is_atom(profile_module) do
    execution_profile in profile_module.allowed_execution_profiles()
  end
end
