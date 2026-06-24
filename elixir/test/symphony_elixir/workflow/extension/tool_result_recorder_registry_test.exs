defmodule SymphonyElixir.Workflow.Extension.ToolResultRecorder.RegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry

  alias __MODULE__.{
    DuplicateIdRecorder,
    EchoRecorder,
    InvalidRecorderExtension,
    RaisingIdRecorder,
    RaisingRecorderExtension,
    RecorderExtension
  }

  test "collects recorder modules from registered extensions" do
    assert {:ok, [entry]} = Registry.entries(entries: [RecorderExtension])

    assert entry.id == "test.tool_result.echo"
    assert entry.module == EchoRecorder
    assert entry.source == {:extension, "test.recorder_extension", RecorderExtension}
  end

  test "fails closed when registry opts are not keyword" do
    assert {:error, %{code: code, reason: :tool_result_recorder_registry_opts_not_keyword, value_type: "map"}} =
             Registry.entries(%{entries: [RecorderExtension]})

    assert code == ErrorCodes.invalid_tool_result_recorder()
  end

  test "fails closed when recorder module opts are not explicit lists" do
    assert {:error, %{code: code, reason: :recorder_modules_not_list, value_type: "atom"}} =
             Registry.entries(recorder_modules: EchoRecorder)

    assert code == ErrorCodes.invalid_tool_result_recorder()

    assert {:error, %{code: ^code, reason: :extra_recorder_modules_not_list, value_type: "atom"}} =
             Registry.entries(entries: [RecorderExtension], extra_recorder_modules: EchoRecorder)
  end

  test "rejects duplicate recorder module contributions" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_tool_result_recorder_modules,
              duplicates: [%{module: module, sources: sources}]
            }} =
             Registry.entries(
               entries: [RecorderExtension],
               extra_recorder_modules: [EchoRecorder]
             )

    assert code == ErrorCodes.invalid_tool_result_recorder()
    assert module == inspect(EchoRecorder)
    recorder_extension = inspect(RecorderExtension)

    assert [
             %{kind: :extension, extension_id: "test.recorder_extension", extension_module: ^recorder_extension},
             :extra_opts
           ] =
             Enum.sort_by(sources, &inspect/1)
  end

  test "rejects duplicate recorder ids" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_tool_result_recorder_ids,
              duplicates: [%{id: "test.tool_result.echo", entries: entries}]
            }} =
             Registry.entries(recorder_modules: [EchoRecorder, DuplicateIdRecorder])

    assert code == ErrorCodes.invalid_tool_result_recorder()
    assert Enum.map(entries, & &1.module) == [inspect(EchoRecorder), inspect(DuplicateIdRecorder)]
  end

  test "fails closed on invalid extension recorder declarations" do
    assert {:error,
            %{
              code: code,
              reason: :tool_result_recorders_not_list,
              extension_id: "test.invalid_recorder_extension",
              value_type: "atom"
            }} =
             Registry.entries(entries: [InvalidRecorderExtension])

    assert code == ErrorCodes.invalid_tool_result_recorder()
  end

  test "bounds extension recorder declaration callback errors" do
    assert {:error,
            %{
              code: code,
              reason: :tool_result_recorders_failed,
              callback_error: %{kind: :error, exception: "RuntimeError"}
            } = error} =
             Registry.entries(entries: [RaisingRecorderExtension])

    assert code == ErrorCodes.invalid_tool_result_recorder()
    refute inspect(error) =~ "secret-recorder-list"
  end

  test "bounds recorder id callback errors" do
    assert {:error,
            %{
              code: code,
              reason: :recorder_id_failed,
              callback_error: %{kind: :error, exception: "RuntimeError"}
            } = error} =
             Registry.entries(recorder_modules: [RaisingIdRecorder])

    assert code == ErrorCodes.invalid_tool_result_recorder()
    refute inspect(error) =~ "secret-recorder-id"
  end

  defmodule EchoRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.echo"

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok
  end

  defmodule DuplicateIdRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: " test.tool_result.echo "

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok
  end

  defmodule RaisingIdRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: raise("secret-recorder-id")

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok
  end

  defmodule RecorderExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.recorder_extension"

    @impl true
    def tool_result_recorders, do: [SymphonyElixir.Workflow.Extension.ToolResultRecorder.RegistryTest.EchoRecorder]

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})
  end

  defmodule InvalidRecorderExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.invalid_recorder_extension"

    @impl true
    def tool_result_recorders, do: :not_a_list

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})
  end

  defmodule RaisingRecorderExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.raising_recorder_extension"

    @impl true
    def tool_result_recorders, do: raise("secret-recorder-list")

    @impl true
    def run_poll_cycle(%RuntimeContext{}, _opts), do: RuntimeResult.replace_extension_state(%{})
  end
end
