defmodule Mix.Tasks.AgentProvider.Smoke do
  use Mix.Task

  alias SymphonyElixir.Agent.DynamicTool.Bridge.Registry
  alias SymphonyElixir.CLI.AgentProviderSmoke, as: AgentProviderSmokeCLI

  @shortdoc "Run agent-provider smoke probes"

  @moduledoc """
  Runs smoke validation against the configured agent provider.

  By default this task creates a temporary empty workspace, starts the selected
  provider, runs one minimal first turn, stops the session, and removes the
  temporary workspace. It does not execute the workflow business prompt and does
  not read or write tracker or repo-provider resources.

  Usage:

      mix agent_provider.smoke [--workflow <path>|--template <alias>] [--prompt <text>] [--start-only] [--json]
  """

  @impl Mix.Task
  def run(args) do
    if Enum.any?(args, &(&1 in ["--help", "-h"])) do
      Mix.shell().info(@moduledoc)
    else
      with :ok <- ensure_runtime_started() do
        {stdout, stderr, exit_code} = without_console_logger(fn -> AgentProviderSmokeCLI.evaluate(args) end)

        if stdout != "", do: IO.write(stdout)

        case exit_code do
          0 ->
            :ok

          _other ->
            message =
              stderr
              |> String.trim()
              |> case do
                "" -> "agent_provider.smoke failed"
                value -> value
              end

            Mix.raise(message)
        end
      end
    end
  end

  defp ensure_runtime_started do
    with {:ok, _logger_apps} <- Application.ensure_all_started(:logger),
         {:ok, _req_apps} <- Application.ensure_all_started(:req),
         {:ok, _yaml_apps} <- Application.ensure_all_started(:yaml_elixir),
         {:ok, _ecto_apps} <- Application.ensure_all_started(:ecto),
         :ok <- ensure_task_supervisor(),
         :ok <- ensure_bridge_context_registry() do
      :ok
    else
      {:error, reason} -> Mix.raise("Failed to start agent-provider smoke runtime dependencies: #{inspect(reason)}")
    end
  end

  defp ensure_task_supervisor do
    case Process.whereis(SymphonyElixir.TaskSupervisor) do
      pid when is_pid(pid) ->
        :ok

      _pid ->
        case Task.Supervisor.start_link(name: SymphonyElixir.TaskSupervisor) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_bridge_context_registry do
    case Process.whereis(Registry) do
      pid when is_pid(pid) ->
        :ok

      _pid ->
        case Registry.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
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
end
