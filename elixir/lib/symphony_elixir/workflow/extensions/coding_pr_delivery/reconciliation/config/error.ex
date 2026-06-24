defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Error do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Contract
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Config.Diagnostics

  @spec format(term()) :: String.t()
  def format(reason) do
    "#{Contract.config_path_name()} is invalid: #{Diagnostics.format(reason)}"
  end
end
