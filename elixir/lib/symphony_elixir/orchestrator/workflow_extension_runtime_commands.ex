defmodule SymphonyElixir.Orchestrator.WorkflowExtensionRuntimeCommands do
  @moduledoc """
  Executes typed workflow-extension commands against orchestrator facilities.

  Workflow extensions emit platform commands without depending on orchestrator
  modules directly. The orchestrator owns this adapter because it controls the
  runtime resources being changed.
  """

  alias SymphonyElixir.Orchestrator.BlockedResourceRegistry
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand

  @type error :: %{
          code: String.t(),
          message: String.t(),
          reason: atom(),
          command: RuntimeCommand.diagnostic()
        }

  @spec handle(term(), keyword()) :: :ok | {:error, error()}
  def handle(command, opts \\ [])

  def handle(
        %RuntimeCommand{
          type: :release_blocked_resource,
          payload: %{resource_kind: resource_kind, resource_id: resource_id, reason: reason}
        },
        opts
      )
      when is_binary(resource_kind) and is_binary(resource_id) and
             ((is_atom(reason) and not is_nil(reason)) or is_binary(reason)) and is_list(opts) do
    BlockedResourceRegistry.release(resource_kind, resource_id, reason, opts)
  end

  def handle(%RuntimeCommand{type: :release_blocked_resource} = command, opts) when is_list(opts) do
    {:error, command_error(:invalid_payload, command)}
  end

  def handle(%RuntimeCommand{} = command, opts) when is_list(opts) do
    {:error, command_error(:unsupported_command_type, command)}
  end

  def handle(command, opts) when is_list(opts) do
    {:error, command_error(:invalid_command, command)}
  end

  defp command_error(reason, command) do
    %{
      code: ErrorCodes.runtime_command_error(),
      message: "Workflow extension runtime command could not be handled by orchestrator.",
      reason: reason,
      command: RuntimeCommand.diagnostic(command)
    }
  end
end
