defmodule SymphonyElixir.CLI.Repo do
  @moduledoc false

  alias SymphonyElixir.CLI.Repo.Options
  alias SymphonyElixir.CLI.Repo.Parser
  alias SymphonyElixir.CLI.Repo.Runner

  @type deps :: %{
          optional(:command_opts) => (-> keyword()),
          optional(:repo_config) => (-> map() | struct() | nil),
          required(:stdout) => (iodata() -> any()),
          required(:stderr) => (iodata() -> any()),
          required(:halt) => (non_neg_integer() -> no_return())
        }

  @spec main([String.t()]) :: no_return()
  def main(argv), do: main(argv, runtime_deps())

  @spec main([String.t()], deps()) :: no_return()
  def main(argv, deps) do
    {stdout, stderr, exit_code} = evaluate(argv, deps)

    if stdout != "", do: deps.stdout.(stdout)
    if stderr != "", do: deps.stderr.(stderr)

    deps.halt.(exit_code)
  end

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps \\ runtime_deps()) do
    case Parser.parse(argv) do
      {:ok, :help} ->
        {Parser.usage(), "", 0}

      {:ok, command, args, opts} ->
        repo_opts = Options.repo_opts(opts, Options.repo_config(deps))
        Runner.run(command, args, repo_opts, opts, Options.command_opts(deps))

      {:error, message} ->
        {"", message <> "\n", 64}
    end
  end

  defp runtime_deps do
    %{
      command_opts: fn -> [] end,
      stdout: &IO.write/1,
      stderr: &IO.write(:stderr, &1),
      halt: &System.halt/1
    }
  end
end
