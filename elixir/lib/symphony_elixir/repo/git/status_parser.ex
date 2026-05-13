defmodule SymphonyElixir.Repo.Git.StatusParser do
  @moduledoc false

  @spec parse(String.t()) :: [map()]
  def parse(""), do: []

  def parse(output) when is_binary(output) do
    output
    |> String.split(<<0>>, trim: true)
    |> parse_tokens([])
    |> Enum.reverse()
  end

  defp parse_tokens([], acc), do: acc

  defp parse_tokens([<<status::binary-size(2), " ", path::binary>> | rest], acc)
       when status in ["R ", "R?", "RM", "RD", "C ", "C?", "CM", "CD"] do
    {original_path, remaining} =
      case rest do
        [original | tail] -> {original, tail}
        [] -> {nil, []}
      end

    entry =
      status
      |> entry(path)
      |> maybe_put_original_path(original_path)

    parse_tokens(remaining, [entry | acc])
  end

  defp parse_tokens([<<status::binary-size(2), " ", path::binary>> | rest], acc) do
    parse_tokens(rest, [entry(status, path) | acc])
  end

  defp parse_tokens([raw | rest], acc) do
    parse_tokens(rest, [%{status: "??", index: "?", worktree: "?", path: raw} | acc])
  end

  defp entry(status, path) do
    %{
      status: status,
      index: String.at(status, 0),
      worktree: String.at(status, 1),
      path: path
    }
  end

  defp maybe_put_original_path(entry, nil), do: entry
  defp maybe_put_original_path(entry, original_path), do: Map.put(entry, :original_path, original_path)
end
