defmodule SymphonyElixir.Orchestrator.WorkflowExtensionRuntimeCommandsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Orchestrator.BlockedResourceRegistry
  alias SymphonyElixir.Orchestrator.WorkflowExtensionRuntimeCommands
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand

  test "releases blocked resources through the orchestrator registry" do
    registry = start_supervised!({BlockedResourceRegistry, name: nil, persistence_path: false})

    assert {:ok, _record} =
             BlockedResourceRegistry.register(
               %{
                 resource_kind: "tracker_issue",
                 resource_id: "issue-1",
                 blocker_code: "missing_change_proposal_target"
               },
               server: registry,
               now_ms: 1_000
             )

    assert :ok =
             RuntimeCommand.release_blocked_issue("issue-1", :known_target_updated)
             |> WorkflowExtensionRuntimeCommands.handle(server: registry, now_ms: 2_000)

    assert [
             %{
               "status" => "released",
               "release_reason" => "known_target_updated",
               "released_at_ms" => 2_000
             }
           ] = BlockedResourceRegistry.snapshot(server: registry)
  end

  test "unsupported commands return stable bounded errors" do
    command = %RuntimeCommand{type: :unsupported_command, payload: %{private_payload: "secret-value"}}

    assert {:error,
            %{
              code: code,
              reason: :unsupported_command_type,
              command: %{command_type: :unsupported_command, payload_type: "map"}
            } = error} = WorkflowExtensionRuntimeCommands.handle(command)

    assert code == ErrorCodes.runtime_command_error()
    refute inspect(error) =~ "secret-value"
    refute inspect(error) =~ "private_payload"
  end

  test "invalid command payloads return stable bounded errors without leaking payload" do
    command = %RuntimeCommand{
      type: :release_blocked_resource,
      payload: %{
        resource_kind: "tracker_issue",
        resource_id: "issue-1",
        reason: %{private_payload: "secret-value"}
      }
    }

    assert {:error,
            %{
              code: code,
              reason: :invalid_payload,
              command: %{
                command_type: :release_blocked_resource,
                payload_type: "map",
                known_payload_fields: [:reason, :resource_id, :resource_kind]
              }
            } = error} = WorkflowExtensionRuntimeCommands.handle(command)

    assert code == ErrorCodes.runtime_command_error()
    refute inspect(error) =~ "secret-value"
    refute inspect(error) =~ "private_payload"
  end

  test "non-command terms return stable bounded errors without leaking payload" do
    command = %{type: :release_blocked_resource, payload: %{private_payload: "secret-value"}}

    assert {:error,
            %{
              code: code,
              reason: :invalid_command,
              command: %{command_type: :release_blocked_resource, payload_type: "map"}
            } = error} = WorkflowExtensionRuntimeCommands.handle(command)

    assert code == ErrorCodes.runtime_command_error()
    refute inspect(error) =~ "secret-value"
    refute inspect(error) =~ "private_payload"
  end
end
