defmodule SymphonyElixir.Workflow.DynamicToolPlan do
  @moduledoc """
  Builds the session-scoped Dynamic Tool allowlist from workflow requirements.
  """

  alias SymphonyElixir.Agent.DynamicTool.{Context, Inventory}
  alias SymphonyElixir.Agent.DynamicTool.Context.ToolPlan
  alias SymphonyElixir.Capability.Registry, as: CapabilityRegistry
  alias SymphonyElixir.Config
  alias SymphonyElixir.Workflow.Capabilities

  @default_exposure :workflow_required

  @type exposure :: :workflow_required | :diagnostics | :all

  @spec from_opts(keyword()) :: {:ok, Context.t()} | {:error, term()}
  def from_opts(opts) when is_list(opts) do
    tool_context = opts |> context_opts() |> Context.from_opts()

    case exposure(opts) do
      :all -> {:ok, put_plan(tool_context, :all, [], [])}
      :diagnostics -> {:ok, restrict_to_diagnostics(tool_context)}
      :workflow_required -> restrict_to_workflow(tool_context, opts)
    end
  end

  defp context_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :workflow_settings) do
      settings when is_map(settings) -> Keyword.put_new(opts, :adoption_settings, settings)
      _settings -> opts
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
         dynamic_tool_capabilities <- Enum.filter(required_capabilities, &typed_workflow_capability?/1),
         {:ok, resolved_tools} <-
           Inventory.resolve_required(tool_context, dynamic_tool_capabilities) do
      tool_names = Enum.map(resolved_tools, & &1.tool)

      {:ok,
       tool_context
       |> Map.put(:adoption_settings, settings)
       |> Context.restrict_tools(tool_names)
       |> put_plan(:workflow_required, required_capabilities, resolved_tools)}
    end
  end

  defp typed_workflow_capability?(capability) when is_binary(capability),
    do: CapabilityRegistry.typed_tool_capability?(capability)

  defp typed_workflow_capability?(_capability), do: false

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
    metadata = Context.metadata_for(tool_context, name)

    cond do
      metadata.operator_only? == true -> [name]
      CapabilityRegistry.diagnostic_capability?(metadata.capability) -> [name]
      true -> []
    end
  end

  defp diagnostics_tool_name(_tool_spec, _tool_context), do: []

  defp put_diagnostics_plan(tool_context, tool_names) do
    Map.put(
      tool_context,
      :tool_plan,
      ToolPlan.new!(
        exposure: "diagnostics",
        required_capabilities: CapabilityRegistry.diagnostic_capabilities(),
        tool_names: tool_names,
        resolved_tools: []
      )
    )
  end

  defp put_plan(tool_context, exposure, required_capabilities, resolved_tools) do
    Map.put(
      tool_context,
      :tool_plan,
      ToolPlan.new!(
        exposure: Atom.to_string(exposure),
        required_capabilities: required_capabilities,
        tool_names: Enum.map(resolved_tools, & &1.tool),
        resolved_tools: resolved_tools
      )
    )
  end

  defp normalize_exposure(:all), do: :all
  defp normalize_exposure("all"), do: :all
  defp normalize_exposure(:diagnostics), do: :diagnostics
  defp normalize_exposure("diagnostics"), do: :diagnostics
  defp normalize_exposure(:workflow_required), do: :workflow_required
  defp normalize_exposure("workflow_required"), do: :workflow_required
  defp normalize_exposure(_exposure), do: @default_exposure
end
