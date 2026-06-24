defmodule SymphonyElixir.Workflow.Extension.Runtime.CommandExecutor do
  @moduledoc """
  Executes typed runtime commands through platform-provided handlers.
  """

  alias SymphonyElixir.Workflow.Extension.Runtime.Error

  @spec execute([term()], keyword()) :: :ok | {:error, map()}
  def execute(commands, opts) when is_list(commands) and is_list(opts) do
    command_handler = Keyword.get(opts, :command_handler, fn _command -> :ok end)

    Enum.reduce_while(commands, :ok, fn command, :ok ->
      case command_handler.(command) do
        :ok -> {:cont, :ok}
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, Error.command(:runtime_command_failed, command, reason)}}
        other -> {:halt, {:error, Error.command(:invalid_runtime_command_result, command, other)}}
      end
    end)
  end
end
