defmodule SymphonyElixir.Workflow.ExecutionProfileRegistry.Resolver do
  @moduledoc false

  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Entry
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Source
  alias SymphonyElixir.Workflow.ExecutionProfileRegistry.Values
  alias SymphonyElixir.Workflow.ProfileRegistry
  alias SymphonyElixir.Workflow.RoutePolicy

  @type resolved_profile :: ProfileRegistry.resolved_profile()

  @spec effective_allowed_execution_profiles(resolved_profile()) :: [String.t()]
  def effective_allowed_execution_profiles(%{module: profile_module, options: profile_options} = profile_context) do
    profile_owned = ProfileRegistry.allowed_execution_profiles(profile_module, profile_options)

    runtime_registered =
      if ProfileRegistry.runtime_execution_profile_extensions_enabled?(profile_module, profile_options) do
        profile_context
        |> matching_entries()
        |> Enum.map(& &1.name)
      else
        []
      end

    (profile_owned ++ runtime_registered)
    |> Enum.uniq()
  end

  @spec resolve(resolved_profile(), String.t(), atom()) ::
          {:ok, {:profile_owned, String.t()} | {:runtime_registered, Entry.t()}} | {:error, term()}
  def resolve(%{module: profile_module, options: profile_options} = profile_context, execution_profile, action)
      when is_binary(execution_profile) do
    normalized_name = Values.normalize_name(execution_profile)
    normalized_action = RoutePolicy.normalize_action(action)

    cond do
      is_nil(normalized_name) ->
        {:error, {:invalid_workflow_execution_profile, execution_profile}}

      normalized_name in ProfileRegistry.allowed_execution_profiles(profile_module, profile_options) ->
        {:ok, {:profile_owned, normalized_name}}

      not ProfileRegistry.runtime_execution_profile_extensions_enabled?(profile_module, profile_options) ->
        {:error, {:unsupported_workflow_execution_profile, normalized_name}}

      true ->
        resolve_runtime_registered(profile_context, normalized_name, normalized_action)
    end
  end

  def resolve(_profile_context, execution_profile, _action),
    do: {:error, {:invalid_workflow_execution_profile, execution_profile}}

  @spec required_capabilities(resolved_profile(), String.t(), atom()) :: [String.t()]
  def required_capabilities(profile_context, execution_profile, action) do
    case resolve(profile_context, execution_profile, action) do
      {:ok, {:runtime_registered, %Entry{} = entry}} -> entry.required_capabilities
      _other -> []
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

  defp resolve_runtime_registered(profile_context, execution_profile, action) do
    case matching_entries(profile_context) |> Enum.find(&(&1.name == execution_profile)) do
      nil ->
        {:error, {:missing_workflow_execution_profile_registry_entry, execution_profile, profile_context.kind, profile_context.version}}

      %Entry{} = entry ->
        if action in entry.supported_actions do
          {:ok, {:runtime_registered, entry}}
        else
          {:error, {:unsupported_workflow_execution_profile_action, execution_profile, action}}
        end
    end
  end
end
