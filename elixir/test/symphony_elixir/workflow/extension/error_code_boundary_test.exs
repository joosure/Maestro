defmodule SymphonyElixir.Workflow.Extension.ErrorCodeBoundaryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension.ErrorCodes

  @runtime_files [
    "lib/symphony_elixir/workflow/extension/diagnostics.ex",
    "lib/symphony_elixir/workflow/extension/registry.ex",
    "lib/symphony_elixir/workflow/extension/registry/collector.ex",
    "lib/symphony_elixir/workflow/extension/registry/config.ex",
    "lib/symphony_elixir/workflow/extension/registry/entry.ex",
    "lib/symphony_elixir/workflow/extension/registry/error.ex",
    "lib/symphony_elixir/workflow/extension/registry/validator.ex",
    "lib/symphony_elixir/workflow/extension/runtime.ex",
    "lib/symphony_elixir/workflow/extension/runtime/command.ex",
    "lib/symphony_elixir/workflow/extension/runtime/command_executor.ex",
    "lib/symphony_elixir/workflow/extension/runtime/context.ex",
    "lib/symphony_elixir/workflow/extension/runtime/dispatcher.ex",
    "lib/symphony_elixir/workflow/extension/runtime/error.ex",
    "lib/symphony_elixir/workflow/extension/runtime/options.ex",
    "lib/symphony_elixir/workflow/extension/runtime/projection.ex",
    "lib/symphony_elixir/workflow/extension/runtime/result_applier.ex",
    "lib/symphony_elixir/workflow/extension/runtime/result.ex",
    "lib/symphony_elixir/workflow/extension/runtime/scope.ex",
    "lib/symphony_elixir/workflow/extension/tool_result_recorder/dispatcher.ex",
    "lib/symphony_elixir/workflow/extension/tool_result_recorder/registry.ex",
    "lib/symphony_elixir/workflow/extension/tool_result_recorder/registry/entry.ex",
    "lib/symphony_elixir/workflow/extension/state_store.ex",
    "lib/symphony_elixir/workflow/extension/state_store/record.ex",
    "lib/symphony_elixir/workflow/extension/state_store/storage/sqlite_backend.ex"
  ]

  test "workflow extension runtime modules read machine codes through the extension code contract" do
    codes = [
      ErrorCodes.invalid_runtime_extension(),
      ErrorCodes.invalid_runtime_extension_options(),
      ErrorCodes.invalid_runtime_context(),
      ErrorCodes.runtime_extension_failed(),
      ErrorCodes.invalid_tool_result_recorder(),
      ErrorCodes.tool_result_recorder_error(),
      ErrorCodes.invalid_state_record(),
      ErrorCodes.state_store_error()
    ]

    offenders =
      for file <- @runtime_files,
          code <- codes,
          source = File.read!(file),
          direct_code_literal?(source, code) do
        {file, code}
      end

    assert offenders == [],
           "workflow extension modules must use Workflow.Extension.ErrorCodes for machine codes; offenders:\n#{format_offenders(offenders)}"
  end

  test "workflow extension error code contract is stable" do
    assert ErrorCodes.invalid_runtime_extension() == "invalid_workflow_runtime_extension"
    assert ErrorCodes.invalid_runtime_extension_options() == "invalid_workflow_runtime_extension_options"
    assert ErrorCodes.invalid_runtime_context() == "invalid_workflow_extension_runtime_context"
    assert ErrorCodes.runtime_extension_failed() == "workflow_runtime_extension_failed"
    assert ErrorCodes.invalid_tool_result_recorder() == "invalid_workflow_extension_tool_result_recorder"
    assert ErrorCodes.tool_result_recorder_error() == "workflow_extension_tool_result_recorder_error"
    assert ErrorCodes.invalid_state_record() == "invalid_workflow_extension_state_record"
    assert ErrorCodes.state_store_error() == "workflow_extension_state_store_error"
  end

  defp direct_code_literal?(source, code) do
    Regex.match?(~r/"#{Regex.escape(code)}"/, source)
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {file, code} -> "- #{file}: #{inspect(code)}" end)
  end
end
