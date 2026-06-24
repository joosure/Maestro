defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.DispatcherTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Dispatcher
  alias __MODULE__.{EchoRecorder, RaisingRecorder, ReturningErrorRecorder}

  test "dispatches only explicit recorder opts to recorder callbacks" do
    assert :ok =
             Dispatcher.record_tool_result(
               "tracker",
               %{private_context: "secret-context"},
               "tracker_attach_external_reference",
               %{"secret" => "argument"},
               {:success, %{"secret" => "payload"}},
               tool_result_recorder_registry_opts: [recorder_modules: [EchoRecorder]],
               tool_result_recorder_opts: [test_pid: self()],
               assembly_secret: "must-not-pass"
             )

    assert_receive {:recorded_opts, [test_pid: pid]} when pid == self()
  end

  test "fails closed on invalid dispatcher option shapes" do
    assert {:error, %{code: code, reason: :dispatcher_opts_not_keyword, value_type: "map"}} =
             Dispatcher.record_tool_result("tracker", %{}, "tool", %{}, {:success, %{}}, %{bad: :opts})

    assert code == ErrorCodes.invalid_tool_result_recorder()

    assert {:error, %{code: ^code, reason: {:dispatcher_option_not_keyword, :tool_result_recorder_registry_opts}, value_type: "atom"}} =
             Dispatcher.record_tool_result("tracker", %{}, "tool", %{}, {:success, %{}}, tool_result_recorder_registry_opts: :bad)

    assert {:error, %{code: ^code, reason: {:dispatcher_option_not_keyword, :tool_result_recorder_opts}, value_type: "atom"}} =
             Dispatcher.record_tool_result("tracker", %{}, "tool", %{}, {:success, %{}}, tool_result_recorder_opts: :bad)
  end

  test "bounds recorder callback returned errors" do
    assert {:error,
            %{
              code: code,
              recorder_id: "test.tool_result.returning_error",
              reason: %{reason: :recorder_failed, value_type: "string"},
              result_type: "success"
            } = error} =
             Dispatcher.record_tool_result(
               "tracker",
               %{private_context: "secret-context"},
               "tracker_attach_external_reference",
               %{"secret" => "argument"},
               {:success, %{"secret" => "payload"}},
               tool_result_recorder_registry_opts: [recorder_modules: [ReturningErrorRecorder]]
             )

    assert code == ErrorCodes.tool_result_recorder_error()
    refute inspect(error) =~ "secret-returned-error"
    refute inspect(error) =~ "secret-context"
    refute inspect(error) =~ "argument"
    refute inspect(error) =~ "payload"
  end

  test "bounds recorder callback exceptions" do
    assert {:error,
            %{
              code: code,
              recorder_id: "test.tool_result.raising",
              reason: %{kind: :error, exception: "RuntimeError"},
              result_type: "success"
            } = error} =
             Dispatcher.record_tool_result(
               "tracker",
               %{private_context: "secret-context"},
               "tracker_attach_external_reference",
               %{"secret" => "argument"},
               {:success, %{"secret" => "payload"}},
               tool_result_recorder_registry_opts: [recorder_modules: [RaisingRecorder]]
             )

    assert code == ErrorCodes.tool_result_recorder_error()
    refute inspect(error) =~ "secret-raise"
    refute inspect(error) =~ "secret-context"
    refute inspect(error) =~ "argument"
    refute inspect(error) =~ "payload"
  end

  defmodule EchoRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.echo"

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:recorded_opts, opts})
      :ok
    end
  end

  defmodule ReturningErrorRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.returning_error"

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: {:error, "secret-returned-error"}
  end

  defmodule RaisingRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.raising"

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: raise("secret-raise")
  end
end
