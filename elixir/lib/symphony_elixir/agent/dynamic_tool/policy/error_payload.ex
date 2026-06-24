defmodule SymphonyElixir.Agent.DynamicTool.Policy.ErrorPayload do
  @moduledoc false

  alias SymphonyElixir.Agent.DynamicTool.Policy.{Contract, Decision, Error}
  alias SymphonyElixir.Platform.DynamicToolBridgeContract.Response

  @spec from_decision(Decision.t()) :: map()
  def from_decision(%Decision{code: code, message: message, details: details}) do
    Response.error_payload(code, message, details)
  end

  @spec from_error(Error.t()) :: map()
  def from_error(%Error{} = error) do
    details =
      %{
        Contract.reason_key() => Atom.to_string(error.reason),
        Contract.field_key() => error.field && Atom.to_string(error.field),
        Contract.value_key() => inspect(error.value)
      }
      |> drop_nil_values()

    Response.error_payload(Contract.invalid_policy(), Contract.invalid_policy_message(), details)
  end

  defp drop_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
