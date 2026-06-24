defmodule SymphonyElixir.Workflow.Extension.StateStore.Record.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @spec invalid(term(), term()) :: map()
  def invalid(reason, value) do
    %{
      code: ErrorCodes.invalid_state_record(),
      message: "Workflow extension state record is invalid.",
      reason: reason,
      value_type: Diagnostics.detailed_type_atom(value)
    }
  end

  @spec canonical(map()) :: map()
  def canonical(reason) do
    %{
      code: ErrorCodes.invalid_state_record(),
      message: "Workflow extension state record is invalid.",
      reason: {:invalid_canonical_identity, Map.get(reason, :reason)},
      codec: Map.get(reason, :codec),
      value_type: Map.get(reason, :value_type)
    }
  end

  @spec format(map()) :: String.t()
  def format(reason) when is_map(reason) do
    code = Map.get(reason, :code, ErrorCodes.invalid_state_record())
    reason_text = format_reason(Map.get(reason, :reason))

    "Workflow extension state record is invalid: code=#{code} reason=#{reason_text}"
  end

  defp format_reason({reason, field}) when is_atom(reason) and is_atom(field) do
    "#{reason}:#{field}"
  end

  defp format_reason({reason, field}) when is_atom(reason) do
    "#{reason}:#{Diagnostics.type_name(field)}"
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "invalid"
end
