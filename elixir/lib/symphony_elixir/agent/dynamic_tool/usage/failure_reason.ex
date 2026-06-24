defmodule SymphonyElixir.Agent.DynamicTool.Usage.FailureReason do
  @moduledoc false

  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @success_key Response.success_key()
  @payload_key Response.payload_key()
  @error_key Response.error_key()
  @code_key Response.code_key()
  @message_key Response.message_key()

  @spec from_response(term()) :: String.t() | nil
  def from_response(%{@success_key => true}), do: nil
  def from_response(%{@payload_key => payload}), do: from_payload(payload)
  def from_response(_response), do: nil

  @spec from_payload(term()) :: String.t() | nil
  def from_payload(%{@error_key => %{@code_key => code}}) when is_binary(code) and code != "", do: code

  def from_payload(%{@error_key => %{@message_key => message}})
      when is_binary(message) and message != "",
      do: message

  def from_payload(_payload), do: nil
end
