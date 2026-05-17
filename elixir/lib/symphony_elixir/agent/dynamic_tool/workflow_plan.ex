defmodule SymphonyElixir.Agent.DynamicTool.WorkflowPlan do
  @moduledoc """
  Builds the session-scoped Dynamic Tool allowlist from workflow requirements.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, Inventory, MetadataContract}
  alias SymphonyElixir.Config
  alias SymphonyElixir.Workflow.Capabilities
  alias SymphonyElixir.Workflow.CapabilityNames

  @default_exposure :workflow_required
  @operator_only_key MetadataContract.operator_only()
  @workflow_capability_key MetadataContract.workflow_capability()

  @type exposure :: :workflow_required | :diagnostics | :all

  @spec from_opts(keyword()) :: {:ok, Context.t()} | {:error, term()}
  def from_opts(opts) when is_list(opts) do
    tool_context = Context.from_opts(opts)

    case exposure(opts) do
      :all -> {:ok, put_plan(tool_context, :all, [], [])}
      :diagnostics -> {:ok, restrict_to_diagnostics(tool_context)}
      :workflow_required -> restrict_to_workflow(tool_context, opts)
    end
  end

  @spec exposure(keyword()) :: exposure()
  def exposure(opts) when is_list(opts) do
    opts
    |> Keyword.get(:dynamic_tool_exposure, @default_exposure)
    |> normalize_exposure()
  end

  defp restrict_to_workflow(tool_context, opts) do
    with {:ok, settings} <- workflow_settings(opts),
         {:ok, required_capabilities, _profile_context} <-
           required_capabilities(settings, Keyword.get(opts, :issue)),
         fallback_policy <- fallback_policy(opts),
         {:ok, resolved_tools} <-
           Inventory.resolve_required(tool_context, required_capabilities, fallback_policy: fallback_policy) do
      tool_names = Enum.map(resolved_tools, & &1.tool)

      {:ok,
       tool_context
       |> Context.restrict_tools(tool_names)
       |> put_plan(:workflow_required, required_capabilities, resolved_tools)}
    end
  end

  defp workflow_settings(opts) do
    case Keyword.get(opts, :workflow_settings) do
      settings when is_map(settings) ->
        {:ok, settings}

      _settings ->
        Config.settings()
    end
  end

  defp required_capabilities(settings, issue) when is_map(issue) do
    Capabilities.required_capabilities_for_issue(settings, issue)
  end

  defp required_capabilities(settings, _issue), do: Capabilities.required_capabilities(settings)

  defp fallback_policy(opts) do
    Keyword.get(
      opts,
      :typed_workflow_tool_fallback_policy,
      Application.get_env(:symphony_elixir, :typed_workflow_tool_fallback_policy, %{})
    )
  end

  defp restrict_to_diagnostics(tool_context) do
    tool_names =
      tool_context
      |> Context.tool_specs()
      |> Enum.flat_map(&diagnostics_tool_name(&1, tool_context))
      |> Enum.uniq()

    tool_context
    |> Context.restrict_tools(tool_names)
    |> put_diagnostics_plan(tool_names)
  end

  defp diagnostics_tool_name(%{"name" => name}, tool_context) when is_binary(name) do
    metadata = Map.get(tool_context.tool_metadata, name, %{})

    cond do
      Map.get(metadata, @operator_only_key) == true -> [name]
      MetadataContract.field_value(metadata, @workflow_capability_key) == CapabilityNames.tracker_provider_diagnostics() -> [name]
      true -> []
    end
  end

  defp diagnostics_tool_name(_tool_spec, _tool_context), do: []

  defp put_diagnostics_plan(tool_context, tool_names) do
    Map.put(tool_context, :tool_plan, %{
      exposure: "diagnostics",
      required_capabilities: [CapabilityNames.tracker_provider_diagnostics()],
      tool_names: tool_names,
      resolved_tools: []
    })
  end

  defp put_plan(tool_context, exposure, required_capabilities, resolved_tools) do
    Map.put(tool_context, :tool_plan, %{
      exposure: Atom.to_string(exposure),
      required_capabilities: required_capabilities,
      tool_names: Enum.map(resolved_tools, & &1.tool),
      resolved_tools: resolved_tools
    })
  end

  defp normalize_exposure(:all), do: :all
  defp normalize_exposure("all"), do: :all
  defp normalize_exposure(:diagnostics), do: :diagnostics
  defp normalize_exposure("diagnostics"), do: :diagnostics
  defp normalize_exposure(:workflow_required), do: :workflow_required
  defp normalize_exposure("workflow_required"), do: :workflow_required
  defp normalize_exposure(_exposure), do: @default_exposure
end
