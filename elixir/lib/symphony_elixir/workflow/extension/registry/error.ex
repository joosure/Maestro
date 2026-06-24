defmodule SymphonyElixir.Workflow.Extension.Registry.Error do
  @moduledoc """
  Bounded error helpers for workflow runtime-extension registry failures.

  The registry implementation uses one stable error envelope so collection,
  validation, and facade code do not grow independent error shapes.
  """

  alias SymphonyElixir.Workflow.Extension.{Diagnostics, ErrorCodes}

  @spec invalid(module() | atom() | nil, atom(), keyword()) :: map()
  def invalid(module, reason, extra \\ []) do
    %{
      code: ErrorCodes.invalid_runtime_extension(),
      message: "Workflow runtime extension registration is invalid.",
      extension_module: inspect(module),
      reason: reason
    }
    |> Map.merge(Map.new(extra))
  end

  @spec format(term()) :: String.t()
  def format(%{message: message, reason: :duplicate_extension_ids, duplicates: duplicates}) do
    "#{message} duplicate_ids=#{format_duplicate_ids(duplicates)}"
  end

  def format(%{message: message, reason: reason, extension_module: module}) do
    "#{message} module=#{module} reason=#{format_reason(reason)}"
  end

  def format(%{message: message, reason: reason}), do: "#{message} reason=#{format_reason(reason)}"
  def format(reason), do: "Workflow runtime extension registration is invalid. reason_type=#{Diagnostics.type_name(reason)}"

  defp format_duplicate_ids(duplicates) do
    Enum.map_join(duplicates, "; ", fn duplicate ->
      entries =
        duplicate
        |> Map.get(:entries, [])
        |> Enum.map_join(",", fn entry -> "#{entry.module}@#{entry.source}" end)

      "#{duplicate.id}=#{entries}"
    end)
  end

  defp format_reason(reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)

  defp format_reason({reason, key}) when is_atom(reason) and is_atom(key) do
    "#{reason}:#{key}"
  end

  defp format_reason(reason), do: "type=#{Diagnostics.type_name(reason)}"
end
