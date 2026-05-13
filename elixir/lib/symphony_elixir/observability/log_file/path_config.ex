defmodule SymphonyElixir.Observability.LogFile.PathConfig do
  @moduledoc false

  @default_log_relative_path "log/symphony.log"

  @spec default_log_file() :: Path.t()
  def default_log_file do
    default_log_file(File.cwd!())
  end

  @spec default_log_file(Path.t()) :: Path.t()
  def default_log_file(logs_root) when is_binary(logs_root) do
    Path.join(logs_root, @default_log_relative_path)
  end

  @spec expand(Path.t()) :: Path.t()
  def expand(path) when is_binary(path), do: Path.expand(path)

  @spec ensure_parent_directory(Path.t()) :: :ok | {:error, File.posix()}
  def ensure_parent_directory(path) when is_binary(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
