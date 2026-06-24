defmodule SymphonyElixir.Platform.DynamicToolBridgeContract.Response do
  @moduledoc """
  JSON response envelope for the Dynamic Tool bridge.

  The bridge is consumed by helper processes and proxied through the worker
  daemon, so the envelope keys are a protocol contract rather than local
  implementation detail.
  """

  @success_key "success"
  @payload_key "payload"
  @error_key "error"
  @code_key "code"
  @message_key "message"
  @reason_key "reason"
  @result_key "result"
  @supported_tools_key "supportedTools"

  @type envelope :: %{required(String.t()) => boolean() | map()}

  @spec success_key() :: String.t()
  def success_key, do: @success_key

  @spec payload_key() :: String.t()
  def payload_key, do: @payload_key

  @spec error_key() :: String.t()
  def error_key, do: @error_key

  @spec code_key() :: String.t()
  def code_key, do: @code_key

  @spec message_key() :: String.t()
  def message_key, do: @message_key

  @spec reason_key() :: String.t()
  def reason_key, do: @reason_key

  @spec result_key() :: String.t()
  def result_key, do: @result_key

  @spec supported_tools_key() :: String.t()
  def supported_tools_key, do: @supported_tools_key

  @spec success(map() | list() | String.t() | number() | boolean() | nil) :: envelope()
  def success(payload), do: %{@success_key => true, @payload_key => payload}

  @spec failure(map() | list() | String.t() | number() | boolean() | nil) :: envelope()
  def failure(payload), do: %{@success_key => false, @payload_key => payload}

  @spec error(String.t()) :: envelope()
  def error(message) when is_binary(message), do: error(nil, message, %{})

  @spec error(String.t() | nil, String.t(), map()) :: envelope()
  def error(code, message, fields \\ %{}) when is_binary(message) and is_map(fields) do
    code
    |> error_payload(message, fields)
    |> failure()
  end

  @spec error_payload(String.t() | nil, String.t(), map()) :: map()
  def error_payload(code, message, fields \\ %{}) when is_binary(message) and is_map(fields) do
    error =
      fields
      |> Map.put(@message_key, message)
      |> maybe_put_code(code)

    %{@error_key => error}
  end

  @spec success?(term()) :: boolean()
  def success?(%{@success_key => true}), do: true
  def success?(_payload), do: false

  defp maybe_put_code(error, code) when is_binary(code) and code != "", do: Map.put(error, @code_key, code)
  defp maybe_put_code(error, _code), do: error
end
