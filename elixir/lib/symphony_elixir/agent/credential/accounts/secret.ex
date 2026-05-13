defmodule SymphonyElixir.Agent.Credential.Accounts.Secret do
  @moduledoc false

  @secret_mode 0o600
  @dir_mode 0o700

  @spec write(Path.t(), String.t()) :: :ok | {:error, File.posix()}
  def write(path, value) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, String.trim(value) <> "\n") do
      File.chmod(path, @secret_mode)
    end
  end

  @spec read(Path.t()) :: String.t() | nil
  def read(path) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> String.trim(contents)
      _error -> nil
    end
  end

  @spec mkdir_private(Path.t()) :: :ok | {:error, File.posix()}
  def mkdir_private(path) do
    with :ok <- File.mkdir_p(path), do: File.chmod(path, @dir_mode)
  end

  @spec copy_optional_file(Path.t(), Path.t(), [Path.t()]) :: [Path.t()]
  def copy_optional_file(source_path, destination_path, copied_files) do
    if File.regular?(source_path) do
      :ok = File.mkdir_p(Path.dirname(destination_path))
      :ok = File.cp(source_path, destination_path)
      :ok = File.chmod(destination_path, @secret_mode)
      [destination_path | copied_files]
    else
      copied_files
    end
  end
end
