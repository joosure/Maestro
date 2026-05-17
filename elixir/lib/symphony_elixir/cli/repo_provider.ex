defmodule SymphonyElixir.CLI.RepoProvider do
  @moduledoc false

  alias SymphonyElixir.CLI.RepoProviderSmoke
  alias SymphonyElixir.Observability.Logger, as: ObservabilityLogger
  alias SymphonyElixir.RepoProvider.CLI.Evaluator

  @type deps :: %{
          required(:env) => (-> %{optional(String.t()) => String.t()} | [{String.t(), String.t()}]),
          optional(:ensure_runtime_started) => (-> :ok | {:error, term()}),
          optional(:with_runtime_logging_suppressed) => ((-> term()) -> term()),
          required(:command_opts) => (-> keyword()),
          required(:stdout) => (iodata() -> any()),
          required(:stderr) => (iodata() -> any()),
          required(:halt) => (non_neg_integer() -> no_return())
        }

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    main(argv, runtime_deps())
  end

  @spec main([String.t()], deps()) :: no_return()
  def main(argv, deps) do
    with_runtime_logging_suppressed(deps, fn ->
      case ensure_runtime_started(deps) do
        :ok ->
          {stdout, stderr, exit_code} = evaluate(argv, deps)

          if stdout != "", do: deps.stdout.(stdout)
          if stderr != "", do: deps.stderr.(stderr)

          deps.halt.(exit_code)

        {:error, reason} ->
          deps.stderr.("Failed to start repo-provider runtime dependencies: #{inspect(reason)}\n")
          deps.halt.(1)
      end
    end)
  end

  @spec evaluate([String.t()], deps()) :: {String.t(), String.t(), non_neg_integer()}
  def evaluate(argv, deps \\ runtime_deps())

  def evaluate(["smoke" | rest], deps) do
    RepoProviderSmoke.evaluate(rest, smoke_deps(deps))
  end

  def evaluate(argv, deps) do
    Evaluator.evaluate(argv, evaluator_deps(deps))
  end

  defp runtime_deps do
    %{
      env: &System.get_env/0,
      command_opts: fn -> [] end,
      stdout: &IO.write/1,
      stderr: &IO.write(:stderr, &1),
      halt: &System.halt/1
    }
  end

  defp ensure_runtime_started(deps) do
    case Map.get(deps, :ensure_runtime_started) do
      nil ->
        ensure_repo_provider_runtime_started()

      fun when is_function(fun, 0) ->
        fun.()
    end
  end

  defp ensure_repo_provider_runtime_started do
    with {:ok, _logger_apps} <- Application.ensure_all_started(:logger),
         {:ok, _req_apps} <- Application.ensure_all_started(:req) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_runtime_logging_suppressed(deps, fun) when is_function(fun, 0) do
    case Map.get(deps, :with_runtime_logging_suppressed) do
      nil -> without_console_logger(fun)
      wrapper when is_function(wrapper, 1) -> wrapper.(fun)
    end
  end

  defp without_console_logger(fun) when is_function(fun, 0) do
    case safe_configure_console_logger(level: :none) do
      {:ok, previous} ->
        try do
          fun.()
        after
          restore_console_logger(previous)
        end

      :skip ->
        fun.()
    end
  end

  defp restore_console_logger(previous) when is_list(previous) do
    _ = safe_configure_console_logger(previous)
    :ok
  end

  defp restore_console_logger(_previous), do: :ok

  defp safe_configure_console_logger(options) do
    {:ok, Logger.configure_backend(:console, options)}
  rescue
    ArgumentError -> :skip
  end

  defp command_opts(deps) do
    case Map.get(deps, :command_opts) do
      nil -> []
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp smoke_deps(deps) do
    %{
      env: deps.env,
      command_opts: fn -> command_opts(deps) end,
      cli_evaluate: &Evaluator.evaluate/2,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: &ObservabilityLogger.emit/3
    }
  end

  defp evaluator_deps(deps) do
    %{
      env: deps.env,
      command_opts: fn -> command_opts(deps) end,
      monotonic_time_ms: fn -> System.monotonic_time(:millisecond) end,
      emit_event: &ObservabilityLogger.emit/3
    }
  end
end
