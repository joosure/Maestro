defmodule SymphonyElixir.RepoProvider.Shell do
  @moduledoc """
  Shared shell command execution for repo-provider adapters.

  Provides an injectable command runner with a default implementation
  that delegates to `System.cmd/3`. Adapters pass `:command_runner`
  in opts to override in tests.

  ## Usage

      import SymphonyElixir.RepoProvider.Shell, only: [run_command: 3, find_executable: 2]

      # Uses default System.cmd runner
      run_command("gh", ["pr", "list"], opts)

      # Tests inject a fake runner via opts
      run_command("gh", ["pr", "list"], command_runner: &my_fake_runner/2)
  """

  alias SymphonyElixir.Platform.CommandEnv

  @spec run_command(String.t(), [String.t()], keyword()) ::
          {:ok, String.t()} | {:error, {non_neg_integer() | atom(), String.t()}}
  def run_command(command, args, opts \\ []) do
    runner = Keyword.get(opts, :command_runner, &default_command_runner/2)
    runner.(command, args)
  end

  @spec find_executable(String.t(), keyword()) :: String.t() | nil
  def find_executable(command, opts \\ []) do
    finder = Keyword.get(opts, :executable_finder, &System.find_executable/1)
    finder.(command)
  end

  @spec default_command_runner(String.t(), [String.t()]) ::
          {:ok, String.t()} | {:error, {non_neg_integer() | atom(), String.t()}}
  def default_command_runner(command, args) do
    case System.find_executable(command) do
      nil ->
        {:error, {:enoent, ""}}

      path ->
        case CommandEnv.system_cmd(path, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, {status, output}}
        end
    end
  end
end
