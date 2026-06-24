defprotocol SymphonyElixir.Agent.DynamicTool.ErrorProjector do
  @moduledoc """
  Protocol for projecting known domain error structs into Dynamic Tool bridge
  error payloads.

  DynamicTool core owns the projection protocol and payload contract, while
  domain modules own their concrete error struct implementations.
  """

  @fallback_to_any true

  @spec project(t()) :: {:ok, map()} | :error
  def project(error)
end

defimpl SymphonyElixir.Agent.DynamicTool.ErrorProjector, for: Any do
  def project(_error), do: :error
end
