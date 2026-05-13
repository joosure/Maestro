defmodule SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Runtime do
  @moduledoc false

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Repo, as: TargetRepo
  alias SymphonyElixir.RepoProvider.Smoke.CNBProvisioner.Settings
  alias SymphonyElixir.RepoProvider.Smoke.ProbeRunner

  @spec mk_temp_dir(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def mk_temp_dir(deps, prefix) do
    case Map.get(deps, :mk_temp_dir) do
      nil -> default_mk_temp_dir(prefix)
      fun when is_function(fun, 1) -> fun.(prefix)
    end
  end

  @spec write_file(map(), String.t(), iodata()) :: :ok | {:error, term()}
  def write_file(deps, path, contents) do
    case Map.get(deps, :write_file) do
      nil -> File.write(path, contents)
      fun when is_function(fun, 2) -> fun.(path, contents)
    end
  end

  @spec rm_rf(map(), String.t()) :: any()
  def rm_rf(deps, path) do
    case Map.get(deps, :rm_rf) do
      nil -> File.rm_rf(path)
      fun when is_function(fun, 1) -> fun.(path)
    end
  end

  @spec sleep_ms(map(), non_neg_integer()) :: any()
  def sleep_ms(deps, milliseconds) do
    case Map.get(deps, :sleep_ms) do
      nil -> Process.sleep(milliseconds)
      fun when is_function(fun, 1) -> fun.(milliseconds)
    end
  end

  @spec repo_command_opts(map(), keyword()) :: keyword()
  def repo_command_opts(deps, opts \\ []) do
    Keyword.put(opts, :command_runner, repo_command_runner(deps))
  end

  @spec cnb_git_auth_config(map()) :: String.t()
  def cnb_git_auth_config(context), do: "http.extraHeader=Authorization: Basic #{Base.encode64("cnb:" <> context.token)}"

  @spec git_identity_config() :: [{String.t(), String.t()}]
  def git_identity_config do
    [
      {"user.name", Settings.git_user_name()},
      {"user.email", Settings.git_user_email()}
    ]
  end

  @spec repo_error_output(TargetRepo.Error.t()) :: String.t()
  def repo_error_output(%TargetRepo.Error{details: %{output: output}}) when is_binary(output), do: output
  def repo_error_output(%TargetRepo.Error{message: message}) when is_binary(message), do: message
  def repo_error_output(error), do: inspect(error)

  @spec repo_error_summary(TargetRepo.Error.t()) :: String.t()
  def repo_error_summary(%TargetRepo.Error{} = error), do: ProbeRunner.summarize_output("", repo_error_output(error))

  defp default_mk_temp_dir(prefix) when is_binary(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive, :monotonic])}")

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_system_cmd(command, argv, opts) do
    CommandEnv.system_cmd(command, argv, Keyword.merge([stderr_to_stdout: true], opts))
  end

  defp run_git_command(deps, argv, opts \\ []) do
    case Map.get(deps, :system_cmd) do
      nil -> default_system_cmd("git", argv, opts)
      fun when is_function(fun, 3) -> fun.("git", argv, Keyword.merge([stderr_to_stdout: true], opts))
    end
  end

  defp repo_command_runner(deps) do
    fn "git", argv ->
      case run_git_command(deps, argv) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, {status, output}}
      end
    end
  end
end
