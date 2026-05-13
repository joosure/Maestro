defmodule SymphonyWorkerDaemon.Session.Server.ResourceBudget do
  @moduledoc false

  @default_output_buffer_bytes 1_048_576

  @spec output_buffer_limit(map(), keyword()) :: pos_integer()
  def output_buffer_limit(request, opts) when is_map(request) and is_list(opts) do
    daemon_limit =
      opts
      |> Keyword.get(:output_buffer_limit, @default_output_buffer_bytes)
      |> normalize_positive_integer()
      |> Kernel.||(@default_output_buffer_bytes)

    case resource_budget_output_limit(request) do
      request_limit when is_integer(request_limit) -> min(daemon_limit, request_limit)
      nil -> daemon_limit
    end
  end

  defp resource_budget_output_limit(%{"resource_budget" => budget}) when is_map(budget) do
    [
      "output_buffer_bytes",
      "output_buffer_limit",
      "max_output_bytes"
    ]
    |> Enum.find_value(fn key ->
      budget
      |> known_budget_value(key)
      |> normalize_positive_integer()
    end)
  end

  defp resource_budget_output_limit(_request), do: nil

  defp known_budget_value(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, known_budget_atom_key(key))
    end
  end

  defp known_budget_atom_key("output_buffer_bytes"), do: :output_buffer_bytes
  defp known_budget_atom_key("output_buffer_limit"), do: :output_buffer_limit
  defp known_budget_atom_key("max_output_bytes"), do: :max_output_bytes
  defp known_budget_atom_key(_key), do: nil

  defp normalize_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp normalize_positive_integer(_value), do: nil
end
