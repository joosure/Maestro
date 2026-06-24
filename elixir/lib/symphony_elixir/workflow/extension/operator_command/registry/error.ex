defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.Registry.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @spec invalid(atom(), keyword()) :: map()
  def invalid(reason, extra \\ []) do
    %{
      code: ErrorCodes.invalid_operator_command(),
      message: "Workflow extension operator command registration is invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end

  @spec invalid_source(module(), atom(), keyword()) :: map()
  def invalid_source(module, reason, extra) do
    invalid(reason, Keyword.put(extra, :extension_module, inspect(module)))
  end

  @spec not_found(String.t(), [term()]) :: map()
  def not_found(command_id, entries) do
    invalid(:operator_command_not_found,
      command_id: command_id,
      available_command_ids: entries |> Enum.map(& &1.id) |> Enum.sort()
    )
  end

  @spec source_diagnostic(term()) :: term()
  def source_diagnostic({:extension, extension_id, extension_module}) do
    %{kind: :extension, extension_id: extension_id, extension_module: inspect(extension_module)}
  end

  def source_diagnostic(source), do: source
end
