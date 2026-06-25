defmodule SymphonyElixir.Workflow.Extension.RuntimeTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.{ErrorCodes, Registry, Runtime}
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Dispatcher, as: OperatorCommandDispatcher
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry, as: OperatorCommandRegistry
  alias SymphonyElixir.Workflow.Extension.Runtime.Command, as: RuntimeCommand
  alias SymphonyElixir.Workflow.Extension.Runtime.Context, as: RuntimeContext
  alias SymphonyElixir.Workflow.Extension.Runtime.Projection, as: RuntimeProjection
  alias SymphonyElixir.Workflow.Extension.Runtime.Result, as: RuntimeResult
  alias SymphonyElixir.Workflow.Extension.Runtime.Scope, as: RuntimeScope
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Dispatcher, as: ToolResultRecorderDispatcher
  alias SymphonyElixir.Workflow.Extension.ToolResultRecorder.Registry, as: ToolResultRecorderRegistry
  alias SymphonyElixir.Workflow.Extensions.CodingPrDelivery

  test "registry returns normalized stable entries" do
    assert {:ok, [entry]} = Registry.entries(entries: [__MODULE__.WhitespaceId])

    assert entry.id == "test.whitespace"
    assert entry.module == __MODULE__.WhitespaceId
    assert entry.source == :opts
  end

  test "registry loads runtime extensions from trusted source modules" do
    assert {:ok, [entry]} = Registry.entries(sources: [__MODULE__.SourceExtension])

    assert entry.id == "test.append_a"
    assert entry.module == __MODULE__.AppendA
    assert entry.source == {:source, __MODULE__.SourceExtension}
  end

  test "registry fails closed on invalid source modules" do
    assert {:error, %{reason: :extension_source_behaviour_missing}} =
             Registry.validate(sources: [__MODULE__.SourceWithoutBehaviour])

    assert {:error, %{reason: :extension_source_modules_not_list}} =
             Registry.validate(sources: [__MODULE__.InvalidSourceReturn])
  end

  test "registry validates configured runtime extension modules" do
    assert :ok = Registry.validate(entries: [__MODULE__.AppendA])

    assert {:error, %{code: code, reason: :extension_behaviour_missing}} =
             Registry.validate(entries: [__MODULE__.MissingBehaviour])

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "registry rejects duplicate extension ids" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_extension_ids,
              duplicates: [%{id: "test.append_a", entries: duplicate_entries}]
            }} =
             Registry.validate(entries: [__MODULE__.AppendA, __MODULE__.WhitespaceDuplicateAppendA])

    assert code == ErrorCodes.invalid_runtime_extension()
    assert Enum.map(duplicate_entries, & &1.module) == [inspect(__MODULE__.AppendA), inspect(__MODULE__.WhitespaceDuplicateAppendA)]

    assert_raise ArgumentError, ~r/duplicate_ids=test\.append_a=/, fn ->
      Registry.validate!(entries: [__MODULE__.AppendA, __MODULE__.WhitespaceDuplicateAppendA])
    end
  end

  test "registry bang errors use bounded diagnostics" do
    assert_raise ArgumentError, ~r/reason=extension_source_modules_not_list/, fn ->
      Registry.validate!(sources: [__MODULE__.InvalidSourceReturn])
    end
  end

  test "registry fails closed on invalid module entries" do
    assert {:error, %{reason: :invalid_extension_module}} = Registry.validate(entries: ["not_a_module"])

    assert {:error, %{reason: :extension_not_loaded}} =
             Registry.validate(entries: [__MODULE__.MissingModule])
  end

  test "registry fails closed on missing callbacks" do
    assert {:error, %{reason: :extension_id_missing}} = Registry.validate(entries: [__MODULE__.MissingId])

    assert {:error, %{reason: :extension_poll_cycle_missing}} =
             Registry.validate(entries: [__MODULE__.MissingRunPollCycle])
  end

  test "registry fails closed on invalid or failing extension ids" do
    assert {:error, %{reason: :extension_id_invalid}} = Registry.validate(entries: [__MODULE__.InvalidId])

    assert {:error, %{reason: :extension_id_failed, callback_error: %{kind: :error}}} =
             Registry.validate(entries: [__MODULE__.RaisingId])
  end

  test "operator command registry derives commands from registered extensions" do
    assert {:ok, [entry]} = OperatorCommandRegistry.entries(entries: [__MODULE__.CommandExtension])

    assert entry.id == "test.operator.echo"
    assert entry.module == __MODULE__.EchoCommand
    assert entry.source == {:extension, "test.command_extension", __MODULE__.CommandExtension}
  end

  test "operator command registry validates Coding PR Delivery commands without platform CLI module coupling" do
    assert {:ok, entries} = OperatorCommandRegistry.entries(entries: [CodingPrDelivery])

    assert Enum.map(entries, & &1.id) == [
             "symphony.workflow.extension.coding_pr_delivery.change_proposal_reconcile",
             "symphony.workflow.extension.coding_pr_delivery.production_profile_plan",
             "symphony.workflow.extension.coding_pr_delivery.production_profile_validate",
             "symphony.workflow.extension.coding_pr_delivery.production_profile_template",
             "symphony.workflow.extension.coding_pr_delivery.production_profile_preflight_collect",
             "symphony.workflow.extension.coding_pr_delivery.production_profile_status"
           ]
  end

  test "tool result recorder registry derives recorders from registered extensions" do
    assert {:ok, [entry]} = ToolResultRecorderRegistry.entries(entries: [__MODULE__.RecorderExtension])

    assert entry.id == "test.tool_result.echo"
    assert entry.module == __MODULE__.EchoToolResultRecorder
    assert entry.source == {:extension, "test.recorder_extension", __MODULE__.RecorderExtension}
  end

  test "tool result recorder registry validates Coding PR Delivery recorders without tracker coupling" do
    assert {:ok, entries} = ToolResultRecorderRegistry.entries(entries: [CodingPrDelivery])

    assert Enum.map(entries, & &1.id) == [
             "symphony.workflow.extension.coding_pr_delivery.tracker_tool_result"
           ]
  end

  test "operator command registry rejects duplicate command ids" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_operator_command_ids,
              duplicates: [%{id: "test.operator.echo", entries: duplicate_entries}]
            }} =
             OperatorCommandRegistry.entries(command_modules: [__MODULE__.EchoCommand, __MODULE__.DuplicateEchoCommand])

    assert code == ErrorCodes.invalid_operator_command()
    assert Enum.map(duplicate_entries, & &1.module) == [inspect(__MODULE__.EchoCommand), inspect(__MODULE__.DuplicateEchoCommand)]
  end

  test "operator command registry fails closed on invalid extension command declarations" do
    assert {:error,
            %{
              code: code,
              reason: :operator_commands_not_list,
              extension_id: "test.invalid_operator_commands"
            }} =
             OperatorCommandRegistry.entries(entries: [__MODULE__.InvalidOperatorCommandsExtension])

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "tool result recorder registry rejects duplicate recorder ids" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_tool_result_recorder_ids,
              duplicates: [%{id: "test.tool_result.echo", entries: duplicate_entries}]
            }} =
             ToolResultRecorderRegistry.entries(recorder_modules: [__MODULE__.EchoToolResultRecorder, __MODULE__.DuplicateEchoToolResultRecorder])

    assert code == ErrorCodes.invalid_tool_result_recorder()
    assert Enum.map(duplicate_entries, & &1.module) == [inspect(__MODULE__.EchoToolResultRecorder), inspect(__MODULE__.DuplicateEchoToolResultRecorder)]
  end

  test "tool result recorder registry fails closed on invalid extension recorder declarations" do
    assert {:error,
            %{
              code: code,
              reason: :tool_result_recorders_not_list,
              extension_id: "test.invalid_tool_result_recorders"
            }} =
             ToolResultRecorderRegistry.entries(entries: [__MODULE__.InvalidToolResultRecordersExtension])

    assert code == ErrorCodes.invalid_tool_result_recorder()
  end

  test "operator-command dispatcher invokes commands by id" do
    assert {"echo first second\n", "", 0} =
             OperatorCommandDispatcher.evaluate("test.operator.echo", ["first", "second"], registry_opts: [entries: [__MODULE__.CommandExtension]])
  end

  test "operator-command dispatcher reports missing commands without concrete module dependencies" do
    assert {"", message, 69} =
             OperatorCommandDispatcher.evaluate("test.operator.missing", [], registry_opts: [entries: [__MODULE__.CommandExtension]])

    assert message =~ "Workflow extension operator command not found"
    assert message =~ "test.operator.missing"
  end

  test "operator-command dispatcher fails closed on invalid option shapes without leaking payloads" do
    assert {"", message, 69} =
             OperatorCommandDispatcher.evaluate(
               "test.operator.echo",
               [],
               registry_opts: %{entries: [__MODULE__.CommandExtension], payload_marker: "private-registry-payload"}
             )

    assert message =~ "Workflow extension operator command registration is invalid"
    assert message =~ "dispatcher_option_not_keyword:registry_opts"
    refute message =~ "private-registry-payload"

    assert {"", message, 69} =
             OperatorCommandDispatcher.evaluate(
               "test.operator.echo",
               [],
               command_opts: [{"payload_marker", "private-command-payload"}]
             )

    assert message =~ "Workflow extension operator command registration is invalid"
    assert message =~ "dispatcher_option_not_keyword:command_opts"
    refute message =~ "private-command-payload"
  end

  test "tool-result recorder dispatcher invokes registered recorders by extension declaration" do
    assert :ok =
             ToolResultRecorderDispatcher.record_tool_result(
               "tracker",
               %{kind: "fake"},
               "tracker_attach_external_reference",
               %{"issue_id" => "ISSUE-1"},
               {:success, %{"status" => "linked"}},
               tool_result_recorder_registry_opts: [entries: [__MODULE__.RecorderExtension]],
               tool_result_recorder_opts: [test_pid: self()]
             )

    assert_receive {:tool_result_recorded, "tracker", "tracker_attach_external_reference", {:success, %{"status" => "linked"}}}
  end

  test "tool-result recorder dispatcher returns bounded errors" do
    assert {:error,
            %{
              code: code,
              recorder_id: "test.tool_result.raising",
              reason: %{kind: :error, exception: "RuntimeError"},
              result_type: "success"
            } = error} =
             ToolResultRecorderDispatcher.record_tool_result(
               "tracker",
               %{private_context: "private-value"},
               "tracker_attach_external_reference",
               %{"private_marker" => "argument"},
               {:success, %{"private_marker" => "payload"}},
               tool_result_recorder_registry_opts: [recorder_modules: [__MODULE__.RaisingToolResultRecorder]]
             )

    assert code == ErrorCodes.tool_result_recorder_error()
    refute inspect(error) =~ "recorder unavailable"
    refute inspect(error) =~ "secret-value"
    refute inspect(error) =~ "argument"
    refute inspect(error) =~ "secret"
  end

  test "runtime extensions execute sequentially through the platform dispatcher" do
    assert {:ok, state} =
             run_poll_cycle(
               %{},
               %{sequence: []},
               entries: [__MODULE__.AppendA, __MODULE__.AppendB],
               metadata: %{poll_id: "poll-1"},
               extension_opts: %{
                 __MODULE__.AppendA => [marker: "module-scoped"],
                 "test.append_b" => [marker: "id-scoped"]
               }
             )

    assert Map.get(state, :sequence) == []

    assert %{
             "test.append_a" => %{sequence: [:a], marker: "module-scoped", poll_id: "poll-1"},
             "test.append_b" => %{sequence: [:b], marker: "id-scoped", observed_a_sequence: [:a]}
           } = state.workflow_extensions
  end

  test "runtime dispatcher normalizes invalid extension returns into stable errors" do
    assert {:error, %{code: code, extension_id: "test.invalid_result", reason: {:invalid_result, :bad_return}}} =
             run_poll_cycle(%{}, %{}, entries: [__MODULE__.InvalidResult])

    assert code == ErrorCodes.runtime_extension_failed()
  end

  test "runtime dispatcher normalizes raised extension callbacks into stable errors" do
    assert {:error,
            %{
              code: code,
              extension_id: "test.raising_poll_cycle",
              reason: %{kind: :error, exception: "RuntimeError"}
            }} =
             run_poll_cycle(%{}, %{}, entries: [__MODULE__.RaisingPollCycle])

    assert code == ErrorCodes.runtime_extension_failed()
  end

  test "runtime command handler failures use bounded diagnostics" do
    command_handler = fn _command ->
      {:error, %{code: "test_handler_error", reason: :failed, payload: %{private_payload: "secret-value"}}}
    end

    assert {:error,
            %{
              code: code,
              extension_id: "test.command_emitter",
              reason: %{
                code: command_code,
                reason: :runtime_command_failed,
                command: %{command_type: :release_blocked_resource, payload_type: "map"},
                handler_result: %{code: "test_handler_error", reason: :failed}
              }
            } = error} =
             run_poll_cycle(%{}, %{}, entries: [__MODULE__.CommandEmitter], command_handler: command_handler)

    assert code == ErrorCodes.runtime_extension_failed()
    assert command_code == ErrorCodes.runtime_command_error()
    refute inspect(error) =~ "secret-value"
    refute inspect(error) =~ "private_payload"
  end

  test "runtime dispatcher fails closed on invalid extension opts shape" do
    assert {:error,
            %{
              code: code,
              reason: :extension_opts_not_keyword_or_map,
              opts_type: "string"
            }} =
             run_poll_cycle(%{}, %{}, entries: [__MODULE__.AppendA], extension_opts: "bad opts")

    assert code == ErrorCodes.invalid_runtime_extension_options()
  end

  test "runtime dispatcher fails closed on unknown extension opts keys" do
    assert {:error,
            %{
              code: code,
              reason: :unknown_extension_opts_keys,
              keys: ["\"test.unknown\""]
            }} =
             run_poll_cycle(%{}, %{},
               entries: [__MODULE__.AppendA],
               extension_opts: %{"test.unknown" => [marker: "ignored"]}
             )

    assert code == ErrorCodes.invalid_runtime_extension_options()
  end

  test "runtime dispatcher fails closed on non-keyword extension opts values" do
    assert {:error,
            %{
              code: code,
              reason: :invalid_extension_opts_value,
              key: "\"test.append_a\"",
              value_type: "map"
            }} =
             run_poll_cycle(%{}, %{},
               entries: [__MODULE__.AppendA],
               extension_opts: %{"test.append_a" => %{marker: "not keyword"}}
             )

    assert code == ErrorCodes.invalid_runtime_extension_options()
  end

  test "coding PR delivery extension fails closed on invalid reconciler opts" do
    assert {:error,
            %{
              code: code,
              extension_id: "symphony.workflow.extension.coding_pr_delivery",
              reason: %{
                code: "invalid_coding_pr_delivery_extension_options",
                reason: :reconciler_opts_not_keyword,
                value_type: :map
              }
            }} =
             run_poll_cycle(%{}, %{},
               entries: [CodingPrDelivery],
               extension_opts: %{
                 CodingPrDelivery.id() => [reconciler_opts: %{not: "keyword"}]
               }
             )

    assert code == ErrorCodes.runtime_extension_failed()
  end

  test "coding PR delivery extension bounds failing reconciler opts functions" do
    assert {:error,
            %{
              code: code,
              extension_id: "symphony.workflow.extension.coding_pr_delivery",
              reason: %{
                code: "invalid_coding_pr_delivery_extension_options",
                reason: :reconciler_opts_function_failed,
                value_type: :function
              }
            }} =
             run_poll_cycle(%{}, %{},
               entries: [CodingPrDelivery],
               extension_opts: %{
                 CodingPrDelivery.id() => [reconciler_opts: fn -> raise "provider payload must not leak" end]
               }
             )

    assert code == ErrorCodes.runtime_extension_failed()
  end

  test "runtime context builds stable workflow scopes through the scope contract" do
    assert {:ok, context} =
             RuntimeContext.new(
               %{workflow: %{profile: %{kind: "missing", version: 99}}},
               %{},
               workflow_scope: %{:profile_kind => "custom", "profile_version" => 1, :nested => [%{"ok" => true}]},
               metadata: %{poll_id: "poll-1"}
             )

    assert context.workflow_scope == %{
             "profile_kind" => "custom",
             "profile_version" => 1,
             "nested" => [%{"ok" => true}]
           }

    assert context.metadata == %{poll_id: "poll-1"}
  end

  test "runtime context derives default workflow scope with normalized field contract" do
    assert {:ok, context} =
             RuntimeContext.new(
               %{workflow: %{profile: %{kind: "missing", version: 99}}},
               %{}
             )

    assert context.workflow_scope[RuntimeScope.profile_kind_key()] == "unknown"
    assert context.workflow_scope[RuntimeScope.profile_version_key()] == 0
    assert context.workflow_scope[RuntimeScope.scope_source_key()] == RuntimeScope.scope_source()
    assert byte_size(context.workflow_scope[RuntimeScope.workflow_config_hash_key()]) == 64
  end

  test "runtime context fails closed on invalid metadata and workflow scope" do
    assert {:error, %{code: code, reason: :metadata_not_map, value_type: "string"}} =
             RuntimeContext.new(%{}, %{}, metadata: "invalid")

    assert code == ErrorCodes.invalid_runtime_context()

    assert {:error, %{code: ^code, reason: :workflow_scope_not_map, value_type: nil}} =
             RuntimeContext.new(%{}, %{}, workflow_scope: nil)

    assert {:error, %{code: ^code, reason: {:invalid_workflow_scope_value, :pid}}} =
             RuntimeContext.new(%{}, %{}, workflow_scope: %{runtime_pid: self()})

    assert_raise ArgumentError, ~r/invalid workflow extension runtime context/, fn ->
      RuntimeContext.new!(%{}, %{}, workflow_scope: %{runtime_pid: self()})
    end
  end

  test "runtime result normalizes supported external field names from the field contract" do
    command = RuntimeCommand.release_blocked_issue("issue-1", :changed)

    external_attrs = %{
      "extension_state" => %{sequence: [:a]},
      "commands" => [command],
      "events" => [%{event: "recorded"}],
      "decisions" => [%{route: "review"}],
      "metadata" => %{extension_id: "test.append_a"}
    }

    assert RuntimeResult.external_field_names() == Enum.map(RuntimeResult.field_keys(), &Atom.to_string/1)

    assert {:ok, result} = RuntimeResult.new(external_attrs)
    assert result.extension_state == %{sequence: [:a]}
    assert result.commands == [command]
    assert result.events == [%{event: "recorded"}]
    assert result.decisions == [%{route: "review"}]
    assert result.metadata == %{extension_id: "test.append_a"}
  end

  test "runtime commands expose stable diagnostics and resource kind contracts" do
    assert RuntimeCommand.tracker_issue_resource_kind() == "tracker_issue"

    assert %RuntimeCommand{
             type: :release_blocked_resource,
             payload: %{resource_kind: "tracker_issue", resource_id: "issue-1", reason: :changed}
           } = RuntimeCommand.release_blocked_issue("issue-1", :changed)

    assert %{payload_type: "missing", known_payload_fields: []} =
             RuntimeCommand.diagnostic(%{type: :release_blocked_resource})
  end

  test "runtime result validation fails closed on unsupported external fields" do
    assert {:error, %{code: code, reason: :unknown_fields}} =
             RuntimeResult.new(%{"extension_state" => %{}, "raw_state" => %{}})

    assert code == ErrorCodes.runtime_extension_failed()
  end

  defmodule AppendA do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.append_a"

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime, metadata: metadata}, opts) do
      runtime
      |> RuntimeProjection.extension_state(id())
      |> append(:a)
      |> Map.put(:marker, Keyword.get(opts, :marker))
      |> Map.put(:poll_id, Map.get(metadata, :poll_id))
      |> RuntimeResult.replace_extension_state()
    end

    defp append(state, value), do: Map.update(state, :sequence, [value], &(&1 ++ [value]))
  end

  defmodule AppendB do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.append_b"

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, opts) do
      append_a_state = RuntimeProjection.extension_state(runtime, "test.append_a")

      runtime
      |> RuntimeProjection.extension_state(id())
      |> Map.update(:sequence, [:b], &(&1 ++ [:b]))
      |> Map.put(:marker, Keyword.get(opts, :marker))
      |> Map.put(:observed_a_sequence, Map.get(append_a_state, :sequence))
      |> RuntimeResult.replace_extension_state()
    end
  end

  defmodule DuplicateAppendA do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.append_a"

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule WhitespaceDuplicateAppendA do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: " test.append_a "

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule WhitespaceId do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: " test.whitespace "

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule InvalidResult do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.invalid_result"

    @impl true
    def run_poll_cycle(_context, _opts), do: :bad_return
  end

  defmodule MissingBehaviour do
    @moduledoc false

    def id, do: "test.missing_behaviour"

    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state("test.missing_behaviour") |> RuntimeResult.replace_extension_state()
  end

  defmodule MissingId do
    @moduledoc false

    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state("test.missing_id") |> RuntimeResult.replace_extension_state()
  end

  defmodule MissingRunPollCycle do
    @moduledoc false

    def id, do: "test.missing_run_poll_cycle"
  end

  defmodule InvalidId do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "Test.Invalid"

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule RaisingId do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: raise("id unavailable")

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state("test.raising_id") |> RuntimeResult.replace_extension_state()
  end

  defmodule SourceExtension do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: [SymphonyElixir.Workflow.Extension.RuntimeTest.AppendA]
  end

  defmodule InvalidSourceReturn do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: :not_a_list
  end

  defmodule SourceWithoutBehaviour do
    @moduledoc false

    def extension_modules(_opts), do: []
  end

  defmodule RaisingPollCycle do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.raising_poll_cycle"

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("poll cycle unavailable")
  end

  defmodule CommandEmitter do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.command_emitter"

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts) do
      runtime
      |> RuntimeProjection.extension_state(id())
      |> RuntimeResult.replace_extension_state(commands: [RuntimeCommand.release_blocked_issue("issue-secret", :changed)])
    end
  end

  defmodule CommandExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.command_extension"

    @impl true
    def operator_commands, do: [SymphonyElixir.Workflow.Extension.RuntimeTest.EchoCommand]

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule InvalidOperatorCommandsExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.invalid_operator_commands"

    @impl true
    def operator_commands, do: :not_a_list

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule RecorderExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.recorder_extension"

    @impl true
    def tool_result_recorders, do: [SymphonyElixir.Workflow.Extension.RuntimeTest.EchoToolResultRecorder]

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule InvalidToolResultRecordersExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.invalid_tool_result_recorders"

    @impl true
    def tool_result_recorders, do: :not_a_list

    @impl true
    def run_poll_cycle(%RuntimeContext{runtime: runtime}, _opts),
      do: runtime |> RuntimeProjection.extension_state(id()) |> RuntimeResult.replace_extension_state()
  end

  defmodule EchoCommand do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

    @impl true
    def id, do: "test.operator.echo"

    @impl true
    def evaluate(argv, _opts), do: {"echo #{Enum.join(argv, " ")}\n", "", 0}
  end

  defmodule DuplicateEchoCommand do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.OperatorCommand

    @impl true
    def id, do: " test.operator.echo "

    @impl true
    def evaluate(_argv, _opts), do: {"duplicate\n", "", 0}
  end

  defmodule EchoToolResultRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.echo"

    @impl true
    def record_tool_result(source_kind, _source_context, tool, _arguments, result, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:tool_result_recorded, source_kind, tool, result})
      :ok
    end
  end

  defmodule DuplicateEchoToolResultRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: " test.tool_result.echo "

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: :ok
  end

  defmodule RaisingToolResultRecorder do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.ToolResultRecorder

    @impl true
    def id, do: "test.tool_result.raising"

    @impl true
    def record_tool_result(_source_kind, _source_context, _tool, _arguments, _result, _opts), do: raise("recorder unavailable")
  end

  defp run_poll_cycle(settings, state, opts) do
    {metadata, opts} = Keyword.pop(opts, :metadata, %{})

    settings
    |> RuntimeContext.new!(state, metadata: metadata)
    |> Runtime.run_poll_cycle(state, opts)
  end
end
