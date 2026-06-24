defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Events.Diagnostics do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics, as: ExtensionDiagnostics

  @allowed_reason_fields [
    :code,
    :reason,
    :kind,
    :exception,
    :reason_type,
    :value_type,
    :error_type,
    :status,
    :provider_kind,
    :retryable
  ]

  @spec error(term()) :: map() | nil
  def error(nil), do: nil
  def error(%_{} = exception), do: ExtensionDiagnostics.exception(exception)

  def error(reason) when is_map(reason) do
    reason
    |> Map.take(@allowed_reason_fields)
    |> normalize_map_reason(reason)
  end

  def error(reason), do: %{reason_type: ExtensionDiagnostics.type_name(reason)}

  defp normalize_map_reason(empty, reason) when map_size(empty) == 0 do
    %{reason_type: ExtensionDiagnostics.type_name(reason)}
  end

  defp normalize_map_reason(reason, _original_reason) when is_map(reason), do: reason
end
