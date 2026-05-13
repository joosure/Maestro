defmodule SymphonyElixir.Agent.Credential.Store.Files do
  @moduledoc false

  @secret_mode 0o600
  @dir_mode 0o700

  @spec secret_mode() :: non_neg_integer()
  def secret_mode, do: @secret_mode

  @spec dir_mode() :: non_neg_integer()
  def dir_mode, do: @dir_mode

  @spec ensure_account_dirs(Path.t()) :: :ok | {:error, term()}
  def ensure_account_dirs(account_dir) do
    with :ok <- mkdir_private(account_dir), do: mkdir_private(Path.join(account_dir, "auth"))
  end

  @spec mkdir_private(Path.t()) :: :ok | {:error, term()}
  def mkdir_private(path) do
    with :ok <- File.mkdir_p(path), do: File.chmod(path, @dir_mode)
  end

  @spec read_json(Path.t(), map()) :: {:ok, map()} | {:error, term()}
  def read_json(path, default) when is_map(default) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, value} when is_map(value) -> {:ok, value}
          {:ok, _value} -> {:ok, default}
          {:error, reason} -> {:error, reason}
        end

      {:error, :enoent} ->
        {:ok, default}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec write_json(Path.t(), map(), non_neg_integer()) :: :ok | {:error, term()}
  def write_json(path, data, mode \\ @secret_mode) when is_map(data) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, Jason.encode!(data, pretty: true) <> "\n") do
      File.chmod(path, mode)
    end
  end
end
