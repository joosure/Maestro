defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @spec invalid(atom(), keyword()) :: map()
  def invalid(reason, extra \\ []) do
    %{
      code: ErrorCodes.invalid_tool_result_recorder(),
      message: "Workflow extension tool-result recorder registration is invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end

  @spec invalid_source(module(), atom(), keyword()) :: map()
  def invalid_source(module, reason, extra) do
    invalid(reason, Keyword.put(extra, :extension_module, inspect(module)))
  end

  @spec source_diagnostic(term()) :: term()
  def source_diagnostic({:extension, extension_id, extension_module}) do
    %{kind: :extension, extension_id: extension_id, extension_module: inspect(extension_module)}
  end

  def source_diagnostic(source), do: source
end
