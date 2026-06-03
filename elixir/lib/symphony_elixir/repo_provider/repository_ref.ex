defmodule SymphonyElixir.RepoProvider.RepositoryRef do
  @moduledoc false

  @spec infer_from_remote_url(String.t() | nil) :: String.t() | nil
  def infer_from_remote_url(nil), do: nil

  def infer_from_remote_url(remote_url) when is_binary(remote_url) do
    remote_url
    |> String.trim()
    |> infer_trimmed_remote_url()
  end

  def infer_from_remote_url(_remote_url), do: nil

  defp infer_trimmed_remote_url(""), do: nil

  defp infer_trimmed_remote_url(remote_url) do
    infer_from_uri(remote_url) || infer_from_scp_like_url(remote_url)
  end

  defp infer_from_uri(remote_url) do
    uri = URI.parse(remote_url)

    cond do
      is_binary(uri.host) and is_binary(uri.path) ->
        normalize_path(uri.path)

      is_nil(uri.host) and is_binary(uri.path) and String.starts_with?(remote_url, "/") ->
        nil

      true ->
        nil
    end
  rescue
    _error -> nil
  end

  defp infer_from_scp_like_url(remote_url) do
    case Regex.run(~r/^[^@\s]+@[^:\s]+:(?<path>.+)$/u, remote_url, capture: :all_names) do
      [path] -> normalize_path(path)
      _other -> nil
    end
  end

  defp normalize_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> String.trim_leading("/")
    |> String.trim_trailing("/")
    |> strip_git_suffix()
    |> valid_repository_path()
  end

  defp normalize_path(_path), do: nil

  defp strip_git_suffix(path) do
    if String.ends_with?(path, ".git") do
      String.slice(path, 0, String.length(path) - 4)
    else
      path
    end
  end

  defp valid_repository_path(""), do: nil

  defp valid_repository_path(path) do
    segments = String.split(path, "/", trim: true)

    cond do
      length(segments) < 2 -> nil
      Enum.any?(segments, &(&1 in [".", ".."])) -> nil
      true -> Enum.join(segments, "/")
    end
  end
end
