defmodule SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.Commands do
  @moduledoc false

  alias SymphonyElixir.Workflow.Extension.Diagnostics
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery.Reconciliation.KnownTarget.Registration.Options

  @spec release_blocked_issue_commands(term(), term()) :: [RuntimeCommand.t()]
  def release_blocked_issue_commands(issue_id, reason)
      when is_binary(issue_id) and ((is_atom(reason) and not is_nil(reason)) or is_binary(reason)) do
    [RuntimeCommand.release_blocked_issue(issue_id, reason)]
  end

  def release_blocked_issue_commands(_issue_id, _reason), do: []

  @spec execute([RuntimeCommand.t()], Options.t()) :: :ok | {:error, term()}
  def execute(commands, %Options{command_handler: nil}) when is_list(commands), do: :ok

  def execute(commands, %Options{command_handler: command_handler}) when is_list(commands) and is_function(command_handler, 1) do
    Enum.reduce_while(commands, :ok, fn command, :ok ->
      case safe_execute(command_handler, command) do
        :ok -> {:cont, :ok}
        {:ok, _result} -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
        other -> {:halt, {:error, {:invalid_runtime_command_result, %{result_type: Diagnostics.detailed_type_atom(other)}}}}
      end
    end)
  end

  defp safe_execute(command_handler, command) do
    command_handler.(command)
  rescue
    error -> {:error, {:runtime_command_handler_failed, Diagnostics.exception(error)}}
  catch
    kind, reason -> {:error, {:runtime_command_handler_failed, Diagnostics.caught(kind, reason)}}
  end
end
