defmodule SymphonyElixir.Workflow.Extension.OperatorCommand.RegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.OperatorCommand
  alias SymphonyElixir.Workflow.Extension.OperatorCommand.Registry

  test "derives command entries from registered extensions" do
    assert {:ok, [entry]} = Registry.entries(entries: [__MODULE__.CommandExtension])

    assert entry.id == "test.operator.echo"
    assert entry.module == __MODULE__.EchoCommand
    assert entry.source == {:extension, "test.command_extension", __MODULE__.CommandExtension}
  end

  test "accepts explicit command module opts as test or assembly override" do
    assert {:ok, [entry]} = Registry.entries(command_modules: [__MODULE__.EchoCommand])

    assert entry.id == "test.operator.echo"
    assert entry.module == __MODULE__.EchoCommand
    assert entry.source == :opts
  end

  test "fails closed when registry opts are not keyword" do
    assert {:error, %{code: code, reason: :operator_command_registry_opts_not_keyword, value_type: "map"}} =
             Registry.entries(%{entries: [__MODULE__.CommandExtension]})

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "fails closed when command_modules opts are not a list" do
    assert {:error,
            %{
              code: code,
              reason: :command_modules_not_list,
              option: :command_modules,
              value_type: "atom"
            }} = Registry.entries(command_modules: __MODULE__.EchoCommand)

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "fails closed when extra_command_modules opts are not a list" do
    assert {:error,
            %{
              code: code,
              reason: :command_modules_not_list,
              option: :extra_command_modules,
              value_type: "atom"
            }} =
             Registry.entries(
               entries: [__MODULE__.CommandExtension],
               extra_command_modules: __MODULE__.DuplicateEchoIdCommand
             )

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "rejects duplicate command module contributions with source diagnostics" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_operator_command_modules,
              duplicates: [%{module: module, sources: sources}]
            }} =
             Registry.entries(
               entries: [__MODULE__.CommandExtension],
               extra_command_modules: [__MODULE__.EchoCommand]
             )

    assert code == ErrorCodes.invalid_operator_command()
    assert module == inspect(__MODULE__.EchoCommand)

    assert sources == [
             %{kind: :extension, extension_id: "test.command_extension", extension_module: inspect(__MODULE__.CommandExtension)},
             :extra_opts
           ]
  end

  test "rejects duplicate command modules contributed by different extensions" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_operator_command_modules,
              duplicates: [%{module: module, sources: sources}]
            }} =
             Registry.entries(entries: [__MODULE__.CommandExtension, __MODULE__.SecondCommandExtension])

    assert code == ErrorCodes.invalid_operator_command()
    assert module == inspect(__MODULE__.EchoCommand)

    assert sources == [
             %{kind: :extension, extension_id: "test.command_extension", extension_module: inspect(__MODULE__.CommandExtension)},
             %{kind: :extension, extension_id: "test.second_command_extension", extension_module: inspect(__MODULE__.SecondCommandExtension)}
           ]
  end

  test "rejects duplicate command ids from distinct command modules" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_operator_command_ids,
              duplicates: [%{id: "test.operator.echo", entries: duplicate_entries}]
            }} =
             Registry.entries(command_modules: [__MODULE__.EchoCommand, __MODULE__.DuplicateEchoIdCommand])

    assert code == ErrorCodes.invalid_operator_command()
    assert Enum.map(duplicate_entries, & &1.module) == [inspect(__MODULE__.EchoCommand), inspect(__MODULE__.DuplicateEchoIdCommand)]
  end

  test "fails closed when a command module is not loaded" do
    assert {:error, %{code: code, reason: :command_not_loaded}} =
             Registry.entries(command_modules: [__MODULE__.MissingCommand])

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "fails closed when a command module does not implement the command behaviour" do
    assert {:error, %{code: code, reason: :command_behaviour_missing}} =
             Registry.entries(command_modules: [__MODULE__.MissingBehaviourCommand])

    assert code == ErrorCodes.invalid_operator_command()
  end

  test "fails closed when extension operator_commands callback raises" do
    assert {:error,
            %{
              code: code,
              reason: :operator_commands_failed,
              extension_id: "test.raising_operator_commands",
              callback_error: %{kind: :error, exception: "RuntimeError"}
            }} = Registry.entries(entries: [__MODULE__.RaisingOperatorCommandsExtension])

    assert code == ErrorCodes.invalid_operator_command()
  end

  defmodule EchoCommand do
    @moduledoc false
    @behaviour OperatorCommand

    @impl true
    def id, do: "test.operator.echo"

    @impl true
    def evaluate(argv, _opts), do: {"echo #{Enum.join(argv, " ")}\n", "", 0}
  end

  defmodule DuplicateEchoIdCommand do
    @moduledoc false
    @behaviour OperatorCommand

    @impl true
    def id, do: " test.operator.echo "

    @impl true
    def evaluate(_argv, _opts), do: {"duplicate\n", "", 0}
  end

  defmodule MissingBehaviourCommand do
    @moduledoc false

    def id, do: "test.operator.missing_behaviour"
    def evaluate(_argv, _opts), do: {"", "", 0}
  end

  defmodule CommandExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.command_extension"

    @impl true
    def operator_commands, do: [SymphonyElixir.Workflow.Extension.OperatorCommand.RegistryTest.EchoCommand]

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("not used")
  end

  defmodule SecondCommandExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.second_command_extension"

    @impl true
    def operator_commands, do: [SymphonyElixir.Workflow.Extension.OperatorCommand.RegistryTest.EchoCommand]

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("not used")
  end

  defmodule RaisingOperatorCommandsExtension do
    @moduledoc false
    @behaviour Extension
    @behaviour Extension.ContributionCallbacks

    @impl true
    def id, do: "test.raising_operator_commands"

    @impl true
    def operator_commands, do: raise("operator command list unavailable")

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("not used")
  end
end
