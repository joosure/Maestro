defmodule SymphonyElixir.Storage.TableCatalogTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Agent.ExecutionPlan.Storage.SQLite.Contract, as: AgentExecutionPlanSQLite
  alias SymphonyElixir.Storage.ErrorCodes
  alias SymphonyElixir.Storage.TableCatalog
  alias SymphonyElixir.Storage.TableCatalog.Entry

  alias SymphonyElixir.Workflow.Extension.StateStore.Storage.SQLite.Contract,
    as: WorkflowExtensionStateSQLite

  alias SymphonyElixir.Workflow.StructuredExecutionPlan.Storage.SQLite.Contract,
    as: WorkflowExecutionPlanSQLite

  @sqlite_contract_glob "lib/symphony_elixir/**/storage/sqlite/contract.ex"

  test "catalog lists current SQLite tables without collisions" do
    assert TableCatalog.duplicate_tables() == []

    assert {:ok, agent_entry} = TableCatalog.fetch(:sqlite, AgentExecutionPlanSQLite.table())
    assert agent_entry.contract_module == AgentExecutionPlanSQLite
    assert agent_entry.owner == :agent_execution_plan

    assert {:ok, workflow_entry} = TableCatalog.fetch(:sqlite, WorkflowExecutionPlanSQLite.table_name())
    assert workflow_entry.contract_module == WorkflowExecutionPlanSQLite
    assert workflow_entry.owner == :workflow_execution_plan_adoption

    assert {:ok, extension_state_entry} = TableCatalog.fetch(:sqlite, WorkflowExtensionStateSQLite.table_name())
    assert extension_state_entry.contract_module == WorkflowExtensionStateSQLite
    assert extension_state_entry.owner == :workflow_extension_state

    refute Enum.any?(TableCatalog.entries(), &(&1.table_name == "change_proposal_known_targets"))
  end

  test "catalog accepts extension entry modules without platform owning their schema" do
    assert {:ok, entry} =
             TableCatalog.fetch(:sqlite, :workflow_plugin_state_records, extra_entry_modules: [__MODULE__.PluginStateContract])

    assert %Entry{} = entry
    assert entry.owner == :workflow_plugin_state
    assert entry.contract_module == __MODULE__.PluginStateContract
    assert entry.payload_schema == "workflow.plugin_state_record.v1"
  end

  test "catalog accepts extension sources without platform owning their schema" do
    source = {__MODULE__.PluginStateSource, entry_modules: [__MODULE__.PluginStateContract]}

    assert {:ok, entry} =
             TableCatalog.fetch(:sqlite, :workflow_plugin_state_records, extra_sources: [source])

    assert %Entry{} = entry
    assert entry.owner == :workflow_plugin_state
    assert entry.contract_module == __MODULE__.PluginStateContract
    assert entry.payload_schema == "workflow.plugin_state_record.v1"
  end

  test "catalog rejects invalid source modules" do
    assert_raise ArgumentError, ~r/must export entry_modules\/1/, fn ->
      TableCatalog.entries(sources: [__MODULE__.PluginStateContract])
    end

    assert_raise ArgumentError, ~r/must implement SymphonyElixir.Storage.TableCatalog.Source/, fn ->
      TableCatalog.entries(sources: [__MODULE__.NoBehaviourSource])
    end
  end

  test "catalog entry normalizes supported external field names from the field contract" do
    external_attrs = %{
      "backend" => :sqlite,
      "owner" => :workflow_plugin_state,
      "table" => :workflow_plugin_state_records,
      "table_name" => "workflow_plugin_state_records",
      "contract_module" => __MODULE__.PluginStateContract,
      "payload_schema" => "workflow.plugin_state_record.v1",
      "purpose" => "Workflow plugin-owned durable state envelopes."
    }

    assert Entry.external_field_names() == Enum.map(Entry.field_keys(), &Atom.to_string/1)

    assert %Entry{} = entry = Entry.new!(external_attrs)
    assert entry.owner == :workflow_plugin_state
    assert entry.contract_module == __MODULE__.PluginStateContract
    assert entry.payload_schema == "workflow.plugin_state_record.v1"
  end

  test "catalog validation fails closed on duplicate table names" do
    assert {:error, %{code: code, duplicates: [_duplicate]}} =
             TableCatalog.validate(entry_modules: [__MODULE__.PluginStateContract, __MODULE__.DuplicatePluginStateContract])

    assert code == ErrorCodes.catalog_invalid()

    assert_raise ArgumentError, ~r/duplicate storage catalog table registrations/, fn ->
      TableCatalog.validate!(entry_modules: [__MODULE__.PluginStateContract, __MODULE__.DuplicatePluginStateContract])
    end
  end

  test "every SQLite storage contract is registered in the platform catalog" do
    registered_contracts =
      TableCatalog.sqlite_entries()
      |> Enum.map(& &1.contract_module)
      |> MapSet.new()

    discovered_contracts =
      sqlite_contract_modules()
      |> MapSet.new()

    assert MapSet.subset?(discovered_contracts, registered_contracts),
           "SQLite storage contracts must be registered in Storage.TableCatalog; missing:\n#{format_modules(MapSet.difference(discovered_contracts, registered_contracts))}"
  end

  test "catalog entries do not own subsystem column or projection details" do
    forbidden_keys = [:columns, :derive_fields, :upsert_replace_columns, :indexes]

    offenders =
      for entry <- TableCatalog.entries(),
          key <- forbidden_keys,
          Map.has_key?(entry, key) do
        {entry.contract_module, key}
      end

    assert offenders == [],
           "Storage.TableCatalog must stay table-level only; offenders:\n#{format_offenders(offenders)}"
  end

  test "catalog entry rejects subsystem schema details" do
    assert_raise ArgumentError, ~r/unsupported field/, fn ->
      Entry.new!(%{
        backend: :sqlite,
        owner: :workflow_plugin_state,
        table: :workflow_plugin_state_records,
        table_name: "workflow_plugin_state_records",
        contract_module: __MODULE__.PluginStateContract,
        payload_schema: "workflow.plugin_state_record.v1",
        purpose: "Workflow plugin-owned durable state envelopes.",
        columns: %{payload: :payload}
      })
    end

    assert_raise ArgumentError, ~r/unsupported field/, fn ->
      Entry.new!(%{
        "backend" => :sqlite,
        "owner" => :workflow_plugin_state,
        "table" => :workflow_plugin_state_records,
        "table_name" => "workflow_plugin_state_records",
        "contract_module" => __MODULE__.PluginStateContract,
        "payload_schema" => "workflow.plugin_state_record.v1",
        "purpose" => "Workflow plugin-owned durable state envelopes.",
        "columns" => %{"payload" => "payload"}
      })
    end
  end

  defp sqlite_contract_modules do
    @sqlite_contract_glob
    |> Path.wildcard()
    |> Enum.map(&module_from_source!/1)
  end

  defp module_from_source!(path) do
    path
    |> File.read!()
    |> then(fn source ->
      case Regex.run(~r/defmodule\s+([A-Za-z0-9_.]+)/, source, capture: :all_but_first) do
        [module_name] -> Module.safe_concat(String.split(module_name, "."))
        _missing -> flunk("Could not find defmodule in #{path}")
      end
    end)
  end

  defp format_modules(modules) do
    modules
    |> MapSet.to_list()
    |> Enum.map_join("\n", &"- #{inspect(&1)}")
  end

  defp format_offenders([]), do: "(none)"

  defp format_offenders(offenders) do
    offenders
    |> Enum.map_join("\n", fn {module, key} -> "- #{inspect(module)} exposes #{inspect(key)}" end)
  end

  defmodule PluginStateContract do
    @moduledoc false

    def catalog_entry do
      %{
        backend: :sqlite,
        owner: :workflow_plugin_state,
        table: :workflow_plugin_state_records,
        table_name: "workflow_plugin_state_records",
        contract_module: __MODULE__,
        payload_schema: "workflow.plugin_state_record.v1",
        purpose: "Workflow plugin-owned durable state envelopes."
      }
    end
  end

  defmodule DuplicatePluginStateContract do
    @moduledoc false

    def catalog_entry do
      %{
        backend: :sqlite,
        owner: :duplicate_plugin_state,
        table: :workflow_plugin_state_records,
        table_name: "workflow_plugin_state_records",
        contract_module: __MODULE__,
        payload_schema: "workflow.plugin_state_record.v1",
        purpose: "Duplicate table fixture."
      }
    end
  end

  defmodule PluginStateSource do
    @moduledoc false

    @behaviour SymphonyElixir.Storage.TableCatalog.Source

    @impl true
    def entry_modules(opts), do: Keyword.fetch!(opts, :entry_modules)
  end

  defmodule NoBehaviourSource do
    @moduledoc false

    def entry_modules(_opts), do: []
  end
end
