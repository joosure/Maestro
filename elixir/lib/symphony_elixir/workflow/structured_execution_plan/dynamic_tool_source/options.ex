defmodule SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.Options do
  @moduledoc """
  Boundary parser for workflow structured execution plan Dynamic Tool exposure.

  The workflow profile decides whether structured execution plan tools are
  enabled. Provider-facing aliases are derived from the runtime provider/tracker
  context and normalized before the executor sees any tool name.
  """

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.AdoptionInitializer.RequestBuilder
  alias SymphonyElixir.Workflow.StructuredExecutionPlan.DynamicToolSource.ProviderContext

  @workflow_settings_key :workflow_settings
  @workflow_settings_key_string "workflow_settings"

  @type provider_context :: ProviderContext.t()

  @spec context(keyword()) :: map()
  def context(opts) when is_list(opts) do
    workflow_settings = keyword_map(opts, @workflow_settings_key)

    %{
      server: Keyword.get(opts, :server) || Keyword.get(opts, :structured_execution_plan_store),
      workflow_settings: workflow_settings,
      provider_contexts: provider_contexts(%{}, opts, workflow_settings)
    }
  end

  @spec enabled?(term(), keyword()) :: boolean()
  def enabled?(source_context, opts \\ []) when is_list(opts) do
    source_context
    |> workflow_settings(opts)
    |> RequestBuilder.enabled?()
  end

  @spec provider_contexts(term(), keyword()) :: [provider_context()]
  def provider_contexts(source_context, opts \\ []) when is_list(opts) do
    workflow_settings = workflow_settings(source_context, opts)
    provider_contexts(source_context, opts, workflow_settings)
  end

  defp workflow_settings(source_context, opts) do
    source_settings =
      if is_map(source_context) do
        map_value(source_context, @workflow_settings_key, @workflow_settings_key_string)
      end

    case source_settings do
      settings when is_map(settings) -> settings
      _settings -> keyword_map(opts, @workflow_settings_key)
    end
  end

  defp provider_contexts(source_context, opts, workflow_settings) do
    [
      ProviderContext.contexts_from_map(source_context),
      opts |> Keyword.get(ProviderContext.provider_contexts_key()) |> ProviderContext.from_input(),
      provider_key_context_from_source_context(source_context),
      opts |> Keyword.get(ProviderContext.tracker_key()) |> ProviderContext.provider_key(),
      provider_key_context_from_workflow_settings(workflow_settings)
    ]
    |> List.flatten()
    |> ProviderContext.from_input()
  end

  defp provider_key_context_from_source_context(source_context) when is_map(source_context) do
    ProviderContext.provider_key(source_context) ||
      source_context
      |> map_value(ProviderContext.tracker_key(), ProviderContext.tracker_string_key())
      |> ProviderContext.provider_key()
  end

  defp provider_key_context_from_source_context(_source_context), do: nil

  defp provider_key_context_from_workflow_settings(workflow_settings) when is_map(workflow_settings) do
    workflow_settings
    |> map_value(ProviderContext.tracker_key(), ProviderContext.tracker_string_key())
    |> ProviderContext.provider_key()
  end

  defp map_value(%{} = map, atom_key, string_key), do: normalize_value(Map.get(map, atom_key) || Map.get(map, string_key))
  defp map_value(_map, _atom_key, _string_key), do: nil

  defp keyword_map(opts, key) do
    case Keyword.get(opts, key) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp normalize_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_value(value), do: value
end
