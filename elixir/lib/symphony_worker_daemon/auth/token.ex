defmodule SymphonyWorkerDaemon.Auth.Token do
  @moduledoc false

  alias SymphonyWorkerDaemon.Auth.Values

  @spec bearer([String.t()]) :: String.t() | nil
  def bearer(headers) when is_list(headers) do
    headers
    |> List.first()
    |> case do
      "Bearer " <> token -> Values.normalize_optional_string(token)
      "bearer " <> token -> Values.normalize_optional_string(token)
      _header -> nil
    end
  end

  @spec match?(String.t(), String.t()) :: boolean()
  def match?(left, right) when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  def match?(_left, _right), do: false
end
