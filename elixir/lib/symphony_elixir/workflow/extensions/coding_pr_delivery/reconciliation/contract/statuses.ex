defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Statuses do
  @moduledoc false

  @reconciliation_ok_status "ok"
  @reconciliation_tracker_error_status "tracker_error"
  @producer_error_status "error"
  @producer_skipped_status "skipped"

  @type reconciliation_status :: :ok | :tracker_error
  @type producer_status :: :error | :skipped

  @spec reconciliation_status(reconciliation_status()) :: String.t()
  def reconciliation_status(:ok), do: @reconciliation_ok_status
  def reconciliation_status(:tracker_error), do: @reconciliation_tracker_error_status

  @spec producer_status(producer_status()) :: String.t()
  def producer_status(:error), do: @producer_error_status
  def producer_status(:skipped), do: @producer_skipped_status
end
