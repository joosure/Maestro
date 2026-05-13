defmodule SymphonyElixir.Repo.Git.Command do
  @moduledoc false

  alias SymphonyElixir.Platform.CommandEnv
  alias SymphonyElixir.Repo.Git.Validation

  @type command_result :: {:ok, String.t()} | {:error, {non_neg_integer() | atom(), String.t()}}

  @spec run(Path.t() | nil, [String.t()], keyword()) :: command_result()
  def run(path, args, opts \\ []) when is_list(args) and is_list(opts) do
    runner = Keyword.get(opts, :command_runner, &default_runner/2)
    runner.("git", scoped_args(path, args, opts))
  end

  @spec default_runner(String.t(), [String.t()]) :: command_result()
  def default_runner(command, args) do
    case System.find_executable(command) do
      nil ->
        {:error, {:enoent, ""}}

      executable ->
        case CommandEnv.system_cmd(executable, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {status, output}}
        end
    end
  end

  defp scoped_args(path, args, opts) do
    args = git_config_args(Keyword.get(opts, :git_config, [])) ++ args

    case Validation.present_string(path) do
      nil -> args
      "." -> args
      repo_path -> ["-C", repo_path] ++ args
    end
  end

  defp git_config_args(config) when is_list(config), do: Enum.flat_map(config, &git_config_arg/1)
  defp git_config_args(config) when is_binary(config), do: git_config_arg(config)
  defp git_config_args(_config), do: []

  defp git_config_arg({key, value}), do: ["-c", "#{key}=#{value}"]
  defp git_config_arg(value) when is_binary(value), do: ["-c", value]
  defp git_config_arg(_value), do: []
end
