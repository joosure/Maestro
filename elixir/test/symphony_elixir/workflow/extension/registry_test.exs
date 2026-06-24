defmodule SymphonyElixir.Workflow.Extension.RegistryTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Workflow.Extension
  alias SymphonyElixir.Workflow.Extension.ErrorCodes
  alias SymphonyElixir.Workflow.Extension.Registry
  alias SymphonyElixir.Workflow.Extension.Registry.Entry

  test "returns normalized stable entries from explicit test assembly opts" do
    assert {:ok, [entry]} = Registry.entries(entries: [__MODULE__.AppendA])

    assert entry.id == "test.append_a"
    assert entry.module == __MODULE__.AppendA
    assert entry.source == :opts
  end

  test "loads runtime extensions from trusted source modules" do
    assert {:ok, [entry]} = Registry.entries(sources: [__MODULE__.SourceAppendA])

    assert entry.id == "test.append_a"
    assert entry.module == __MODULE__.AppendA
    assert entry.source == {:source, __MODULE__.SourceAppendA}
  end

  test "fails closed when opts are not keyword" do
    assert {:error, %{code: code, reason: :registry_opts_not_keyword, value_type: :list}} =
             Registry.entries([:not_keyword])

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "fails closed on unknown opts" do
    assert {:error, %{code: code, reason: :registry_opts_unknown_keys, keys: [":unknown"]}} =
             Registry.entries(entries: [__MODULE__.AppendA], unknown: true)

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "fails closed when entry opts are not lists" do
    assert {:error,
            %{
              code: code,
              reason: :extension_modules_not_list,
              option: :entries,
              value_type: :atom
            }} = Registry.entries(entries: __MODULE__.AppendA)

    assert code == ErrorCodes.invalid_runtime_extension()

    assert {:error,
            %{
              code: code,
              reason: :extension_modules_not_list,
              option: :extra_entries,
              value_type: :atom
            }} = Registry.entries(entries: [], extra_entries: __MODULE__.AppendA)

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "fails closed when source opts are not lists" do
    assert {:error,
            %{
              code: code,
              reason: :extension_sources_not_list,
              option: :sources,
              value_type: :atom
            }} = Registry.entries(sources: __MODULE__.SourceAppendA)

    assert code == ErrorCodes.invalid_runtime_extension()

    assert {:error,
            %{
              code: code,
              reason: :extension_sources_not_list,
              option: :extra_sources,
              value_type: :atom
            }} = Registry.entries(entries: [], extra_sources: __MODULE__.SourceAppendA)

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "fails closed when source_opts is not keyword" do
    assert {:error, %{code: code, reason: :source_opts_not_keyword, value_type: :map}} =
             Registry.entries(sources: [__MODULE__.SourceAppendA], source_opts: %{})

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "rejects duplicate extension module contributions with source diagnostics" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_extension_modules,
              duplicates: [%{module: module, sources: sources}]
            }} =
             Registry.entries(
               entries: [__MODULE__.AppendA],
               extra_entries: [__MODULE__.AppendA]
             )

    assert code == ErrorCodes.invalid_runtime_extension()
    assert module == inspect(__MODULE__.AppendA)
    assert sources == [:opts, :extra_opts]
  end

  test "rejects duplicate extension modules contributed by different sources" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_extension_modules,
              duplicates: [%{module: module, sources: sources}]
            }} = Registry.entries(sources: [__MODULE__.SourceAppendA, __MODULE__.SecondSourceAppendA])

    assert code == ErrorCodes.invalid_runtime_extension()
    assert module == inspect(__MODULE__.AppendA)

    assert sources == [
             %{kind: :source, source_module: inspect(__MODULE__.SourceAppendA)},
             %{kind: :source, source_module: inspect(__MODULE__.SecondSourceAppendA)}
           ]
  end

  test "rejects duplicate extension ids from distinct modules" do
    assert {:error,
            %{
              code: code,
              reason: :duplicate_extension_ids,
              duplicates: [%{id: "test.append_a", entries: duplicate_entries}]
            }} = Registry.entries(entries: [__MODULE__.AppendA, __MODULE__.DuplicateAppendA])

    assert code == ErrorCodes.invalid_runtime_extension()
    assert Enum.map(duplicate_entries, & &1.module) == [inspect(__MODULE__.AppendA), inspect(__MODULE__.DuplicateAppendA)]
  end

  test "fails closed on source callback failures" do
    assert {:error,
            %{
              code: code,
              reason: :extension_source_failed,
              callback_error: %{kind: :error, exception: "RuntimeError"}
            }} = Registry.entries(sources: [__MODULE__.RaisingSource])

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "fails closed when a source returns a non-list" do
    assert {:error, %{code: code, reason: :extension_source_modules_not_list, value_type: :atom}} =
             Registry.entries(sources: [__MODULE__.InvalidSourceReturn])

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  test "entry source accepts only known registration sources" do
    assert {:error, %{code: code, reason: :extension_source_invalid}} = Entry.new(__MODULE__.AppendA, :config)

    assert code == ErrorCodes.invalid_runtime_extension()
  end

  defmodule AppendA do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: "test.append_a"

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("not used")
  end

  defmodule DuplicateAppendA do
    @moduledoc false
    @behaviour Extension

    @impl true
    def id, do: " test.append_a "

    @impl true
    def run_poll_cycle(_context, _opts), do: raise("not used")
  end

  defmodule SourceAppendA do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: [SymphonyElixir.Workflow.Extension.RegistryTest.AppendA]
  end

  defmodule SecondSourceAppendA do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: [SymphonyElixir.Workflow.Extension.RegistryTest.AppendA]
  end

  defmodule RaisingSource do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: raise("source unavailable")
  end

  defmodule InvalidSourceReturn do
    @moduledoc false
    @behaviour SymphonyElixir.Workflow.Extension.Registry.Source

    @impl true
    def extension_modules(_opts), do: :not_a_list
  end
end
