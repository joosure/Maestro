defmodule SymphonyElixir.Repo.Git.Output do
  @moduledoc false

  @spec joined([String.t()]) :: String.t()
  def joined(outputs), do: joined(outputs, "synced")

  @spec joined([String.t()], String.t()) :: String.t()
  def joined(outputs, default) when is_list(outputs) and is_binary(default) do
    outputs
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> default
      lines -> Enum.join(lines, "\n")
    end
  end
end
