defmodule SymphonyElixir.Workflow.Extension.Runtime.Error do
  @moduledoc """
  Bounded error envelopes for the workflow extension runtime mechanism.
  """

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand

  @spec extension(map(), term()) :: map()
  def extension(entry, reason) do
    %{
      code: ErrorCodes.runtime_extension_failed(),
      message: "Workflow runtime extension failed during poll cycle.",
      extension_id: entry.id,
      extension_module: inspect(entry.module),
      reason: reason
    }
  end

  @spec options(atom(), keyword()) :: map()
  def options(reason, extra) when is_atom(reason) and is_list(extra) do
    %{
      code: ErrorCodes.invalid_runtime_extension_options(),
      message: "Workflow runtime extension options are invalid.",
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end

  @spec command(atom(), term(), term()) :: map()
  def command(reason, command, handler_result) when is_atom(reason) do
    %{
      code: ErrorCodes.runtime_command_error(),
      message: "Workflow extension runtime command failed during platform execution.",
      reason: reason,
      command: RuntimeCommand.diagnostic(command),
      handler_result: handler_result_diagnostic(handler_result)
    }
  end

  defp handler_result_diagnostic(%{code: code, reason: reason}) when is_binary(code) and is_atom(reason) do
    %{code: code, reason: reason}
  end

  defp handler_result_diagnostic(%{code: code, reason: reason}) when is_binary(code) and is_binary(reason) do
    %{code: code, reason: reason}
  end

  defp handler_result_diagnostic(reason) when is_atom(reason) and not is_nil(reason), do: reason
  defp handler_result_diagnostic(reason) when is_binary(reason), do: String.slice(reason, 0, 256)
  defp handler_result_diagnostic(reason), do: %{type: Diagnostics.type_name(reason)}
end
