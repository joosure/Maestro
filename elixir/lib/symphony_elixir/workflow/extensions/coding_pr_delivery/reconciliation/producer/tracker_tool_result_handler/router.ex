defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Router do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.HostAdapters.Reconciliation.ProducerDefaults, as: Defaults
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultFields, as: ToolFields
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Producer.TrackerToolResultHandler.Values

  @spec capability(map(), String.t(), keyword()) :: String.t() | nil
  def capability(tracker, tool, opts) when is_map(tracker) and is_binary(tool) do
    if Keyword.keyword?(opts) do
      tool_context_capability(tool, Keyword.get(opts, :tool_context)) ||
        tracker_tool_spec_capability(tracker, tool)
    end
  end

  @spec diagnostics_enabled?(keyword()) :: boolean()
  def diagnostics_enabled?(opts) do
    Keyword.keyword?(opts) and
      (Keyword.get(opts, :tracker_tool_result_diagnostics?, false) == true or
         Keyword.get(opts, :dynamic_tool_exposure) in [:diagnostics, ToolFields.diagnostics_exposure()] or
         tool_context_exposure(Keyword.get(opts, :tool_context)) == ToolFields.diagnostics_exposure())
  end

  defp tool_context_capability(tool, tool_context) when is_map(tool_context) do
    tool_context
    |> Values.map_value(ToolFields.tool_metadata())
    |> tool_metadata(tool)
    |> workflow_capability()
  end

  defp tool_context_capability(_tool, _tool_context), do: nil

  defp tool_metadata(metadata, tool) when is_map(metadata), do: Map.get(metadata, tool)
  defp tool_metadata(_metadata, _tool), do: nil

  defp tracker_tool_spec_capability(tracker, tool) do
    tracker
    |> Defaults.dynamic_tools()
    |> Enum.find(fn spec -> Values.string_value(spec, ToolFields.name()) == tool end)
    |> workflow_capability()
  end

  defp workflow_capability(spec) when is_map(spec) do
    Values.string_value(spec, ToolFields.workflow_capability())
  end

  defp workflow_capability(_spec), do: nil

  defp tool_context_exposure(tool_context) when is_map(tool_context) do
    case tool_context |> Values.map_value(ToolFields.tool_plan()) |> Values.map_value(ToolFields.exposure()) do
      exposure when is_binary(exposure) -> exposure
      _exposure -> nil
    end
  end

  defp tool_context_exposure(_tool_context), do: nil
end
