defmodule SymphonyElixir.Config.Capabilities do
  @moduledoc """
  Collects provider-owned logical capabilities from resolved application config.

  This module sits at the config/provider integration boundary. Workflow Core
  consumes the resulting capability set but does not know how providers are
  registered or configured.
  """

  alias SymphonyElixir.Agent.DynamicTool.MetadataContract
  alias SymphonyElixir.AgentProvider
  alias SymphonyElixir.RepoProvider
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Capabilities, as: WorkflowCapabilities
  alias SymphonyElixir.Workflow.CapabilityNames

  @repo_capabilities CapabilityNames.repo_core()

  @repo_provider_capability_map %{
    pr_create: CapabilityNames.repo_provider_change_proposal_create(),
    pr_view: CapabilityNames.repo_provider_change_proposal_read(),
    pr_reviews: CapabilityNames.repo_provider_review_read(),
    pr_checks: CapabilityNames.repo_provider_check_read(),
    pr_merge: CapabilityNames.repo_provider_merge()
  }

  @spec available_capabilities(map()) :: MapSet.t(WorkflowCapabilities.capability())
  def available_capabilities(settings) when is_map(settings) do
    [
      tracker_capabilities(settings),
      repo_capabilities(settings),
      repo_provider_capabilities(settings),
      repo_provider_typed_tool_capabilities(settings),
      agent_provider_capabilities(settings)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp tracker_capabilities(settings) do
    settings
    |> map_field(:tracker)
    |> tracker_kind()
    |> Tracker.adapter_for()
    |> module_capabilities()
  end

  defp repo_capabilities(settings) do
    case map_field(settings, :repo) do
      repo when is_map(repo) -> @repo_capabilities
      _ -> []
    end
  end

  defp repo_provider_capabilities(settings) do
    settings
    |> map_field(:repo)
    |> RepoProvider.capabilities()
    |> Enum.flat_map(&repo_provider_capability/1)
  end

  defp repo_provider_typed_tool_capabilities(settings) do
    settings
    |> map_field(:repo)
    |> case do
      repo when is_map(repo) -> RepoProvider.dynamic_tools(repo)
      _repo -> []
    end
    |> Enum.flat_map(&typed_tool_capability/1)
  end

  defp agent_provider_capabilities(settings) do
    settings
    |> map_field(:agent_provider)
    |> agent_provider_kind()
    |> AgentProvider.adapter_for()
    |> module_capabilities()
  end

  defp module_capabilities(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :capabilities, 0) do
      module.capabilities()
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
    else
      []
    end
  end

  defp module_capabilities(_module), do: []

  defp repo_provider_capability(capability) do
    case Map.fetch(@repo_provider_capability_map, capability) do
      {:ok, logical_capability} -> [logical_capability]
      :error -> []
    end
  end

  defp typed_tool_capability(tool) when is_map(tool) do
    case MetadataContract.field_value(tool, MetadataContract.workflow_capability()) do
      capability when is_binary(capability) -> [capability]
      _capability -> []
    end
  end

  defp typed_tool_capability(_tool), do: []

  defp tracker_kind(tracker) when is_map(tracker), do: map_field(tracker, :kind)
  defp tracker_kind(_tracker), do: nil

  defp agent_provider_kind(agent_provider) when is_map(agent_provider), do: map_field(agent_provider, :kind)
  defp agent_provider_kind(_agent_provider), do: nil

  defp map_field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_field(_map, _key), do: nil
end
