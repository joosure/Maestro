defmodule SymphonyWorkerDaemon.Session.Server.RequestFingerprint do
  @moduledoc false

  @spec fingerprint(map()) :: String.t()
  def fingerprint(request) when is_map(request) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(canonical_term(request)))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(value), do: value
end
