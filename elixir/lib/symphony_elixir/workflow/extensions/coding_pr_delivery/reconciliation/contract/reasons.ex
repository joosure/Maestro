defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.Contract.Reasons do
  @moduledoc false

  @spec reason_name(atom() | String.t()) :: String.t()
  def reason_name(reason) when is_atom(reason), do: Atom.to_string(reason)
  def reason_name(reason) when is_binary(reason), do: reason
end
