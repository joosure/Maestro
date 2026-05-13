defmodule SymphonyElixir.CLI.Repo.Renderer do
  @moduledoc false

  alias SymphonyElixir.Repo.Error
  alias SymphonyElixir.Repo.Preflight
  alias SymphonyElixir.Repo.Status

  @type output :: {String.t(), String.t(), non_neg_integer()}

  @spec scalar(term()) :: output()
  def scalar({:ok, value}) when is_binary(value), do: {value <> "\n", "", 0}
  def scalar({:ok, :noop}), do: {"noop\n", "", 0}
  def scalar({:error, %Error{} = error}), do: error(error)

  @spec status(term()) :: output()
  def status({:ok, %Status{} = status}) do
    stdout =
      [
        "state=#{status.state}",
        maybe_line("root", status.root),
        maybe_line("branch", status.branch),
        maybe_line("head_sha", status.head_sha),
        "entries=#{length(status.entries)}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    {stdout <> "\n", "", 0}
  end

  def status({:error, %Error{} = error}), do: error(error)

  @spec preflight(term()) :: output()
  def preflight({:ok, %Preflight{} = preflight}) do
    stdout =
      [
        "state=ready",
        "path=#{preflight.path}",
        "root=#{preflight.root}",
        "remote=#{preflight.remote}",
        "remote_url=#{preflight.remote_url}",
        "base_branch=#{preflight.base_branch}",
        "current_branch=#{preflight.current_branch}",
        "head_sha=#{preflight.head_sha}"
      ]
      |> Enum.join("\n")

    {stdout <> "\n", "", 0}
  end

  def preflight({:error, %Error{} = error}), do: error(error)

  @spec error(Error.t()) :: output()
  def error(%Error{} = error) do
    message =
      case error.message do
        message when is_binary(message) and message != "" -> message
        _other -> inspect(error)
      end

    {"", message <> "\n", error.exit_code}
  end

  defp maybe_line(_key, nil), do: nil
  defp maybe_line(_key, ""), do: nil
  defp maybe_line(key, value), do: "#{key}=#{value}"
end
