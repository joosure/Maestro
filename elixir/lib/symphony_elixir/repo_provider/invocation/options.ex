defmodule SymphonyElixir.RepoProvider.Invocation.Options do
  @moduledoc false

  alias SymphonyElixir.RepoProvider.Error

  @spec fields(String.t()) :: [String.t()]
  def fields(fields) do
    fields
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec body_file(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def body_file(path) do
    case File.read(path) do
      {:ok, body} ->
        {:ok, body}

      {:error, reason} ->
        {:error, Error.invalid_invocation("Unable to read --body-file #{path}: #{:file.format_error(reason)}")}
    end
  end
end
