defmodule Mix.Tasks.Workflow.Command do
  use Mix.Task

  alias SymphonyElixir.Observability.EventStore
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Dispatcher

  @shortdoc "Run a registered workflow extension operator command"

  @moduledoc """
  Runs a registered workflow extension operator command by command id.

  Platform Mix tasks provide the stable operator entrypoint. Concrete command
  arguments, validation, output rendering, and business execution stay in the
  owning workflow extension command module.

  Usage:

      mix workflow.command --id <command-id> -- [command args]
      mix workflow.command <command-id> -- [command args]

  Examples:

      mix workflow.command --id <command-id> -- --help
      mix workflow.command --id <command-id> -- [command args]
  """

  @switches [
    id: :string,
    help: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    if Enum.any?(args, &(&1 in ["--help", "-h"])) and not Enum.member?(args, "--") do
      Mix.shell().info(@moduledoc)
    else
      run_parsed(args)
    end
  end

  defp run_parsed(args) do
    case parse(args) do
      {:ok, command_id, command_args} ->
        with :ok <- ensure_runtime_started() do
          command_id
          |> Dispatcher.evaluate(command_args)
          |> handle_result()
        end

      {:error, message} ->
        Mix.raise(message <> "\n" <> @moduledoc)
    end
  end

  defp handle_result({stdout, stderr, exit_code}) do
    if stdout != "", do: IO.write(stdout)

    case exit_code do
      0 ->
        :ok

      _other ->
        stderr
        |> failure_message()
        |> Mix.raise()
    end
  end

  defp failure_message(stderr) do
    case String.trim(stderr) do
      "" -> "workflow.command failed"
      value -> value
    end
  end

  defp parse(args) do
    {task_args, command_args} = split_command_args(args)

    case OptionParser.parse(task_args, strict: @switches, aliases: [h: :help]) do
      {opts, positional, []} ->
        command_id_values = Keyword.get_values(opts, :id)

        cond do
          Keyword.get(opts, :help, false) ->
            {:error, "Pass command help after --, for example: mix workflow.command --id <command-id> -- --help"}

          length(command_id_values) > 1 ->
            {:error, "Pass only one --id value"}

          command_id_values != [] and positional != [] ->
            {:error, "Pass command id either as --id or as the first positional argument, not both"}

          command_id_values != [] ->
            {:ok, List.last(command_id_values), command_args}

          length(positional) == 1 ->
            {:ok, List.first(positional), command_args}

          positional == [] ->
            {:error, "--id or command id is required"}

          true ->
            {:error, "Pass only one command id"}
        end

      {_opts, _positional, invalid} ->
        {:error, "Invalid workflow.command option(s): #{inspect(invalid)}"}
    end
  end

  defp split_command_args(args) do
    case Enum.split_while(args, &(&1 != "--")) do
      {task_args, ["--" | command_args]} -> {task_args, command_args}
      {task_args, []} -> {task_args, []}
    end
  end

  defp ensure_runtime_started do
    with {:ok, _logger_apps} <- Application.ensure_all_started(:logger),
         {:ok, _req_apps} <- Application.ensure_all_started(:req),
         {:ok, _yaml_apps} <- Application.ensure_all_started(:yaml_elixir),
         :ok <- ensure_event_store_started() do
      :ok
    else
      {:error, reason} -> Mix.raise("Failed to start workflow command runtime dependencies: #{inspect(reason)}")
    end
  end

  defp ensure_event_store_started do
    case Process.whereis(EventStore) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case EventStore.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
