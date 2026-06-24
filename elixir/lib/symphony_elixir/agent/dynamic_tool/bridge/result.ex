defmodule SymphonyElixir.Agent.DynamicTool.Bridge.Result do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.{ErrorProjector, Serializer}
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @type bridge_result :: %{required(String.t()) => boolean() | map()}

  @spec normalize(term()) :: bridge_result()
  def normalize({:success, payload}) do
    Response.success(Serializer.json_safe_value(payload))
  end

  def normalize({:failure, payload}) do
    failure(payload)
  end

  def normalize({:error, reason}) do
    case ErrorProjector.project(reason) do
      {:ok, error_payload} ->
        failure(%{Response.error_key() => error_payload})

      :error ->
        failure(Response.error_payload(nil, "Dynamic tool execution failed.", %{Response.reason_key() => inspect(reason)}))
    end
  end

  def normalize(result) do
    failure(
      Response.error_payload(nil, "Dynamic tool execution returned an invalid result.", %{
        Response.result_key() => inspect(result)
      })
    )
  end

  @spec failure(term()) :: bridge_result()
  def failure(payload) do
    Response.failure(Serializer.json_safe_value(payload))
  end
end
