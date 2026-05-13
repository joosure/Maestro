defmodule SymphonyWorkerDaemon.Session.Server.TimeoutPolicy do
  @moduledoc false

  @spec timeout_ms(map(), String.t()) :: pos_integer() | nil
  def timeout_ms(%{"timeout_policy" => timeout_policy}, key) when is_map(timeout_policy) and is_binary(key) do
    timeout_policy
    |> known_policy_value(key)
    |> normalize_positive_integer()
  end

  def timeout_ms(_request, _key), do: nil

  defp known_policy_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, known_policy_atom_key(key))
    end
  end

  defp known_policy_atom_key("session_timeout_ms"), do: :session_timeout_ms
  defp known_policy_atom_key("startup_timeout_ms"), do: :startup_timeout_ms
  defp known_policy_atom_key("idle_timeout_ms"), do: :idle_timeout_ms
  defp known_policy_atom_key(_key), do: nil

  defp normalize_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp normalize_positive_integer(_value), do: nil
end
