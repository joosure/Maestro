defmodule SymphonyElixir.Workflow.Extension.RegistryConfigTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Workflow.Extension.Registry

  @app :symphony_elixir
  @config_key :workflow_runtime_extensions

  setup do
    original = Application.get_env(@app, @config_key)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(@app, @config_key)
        value -> Application.put_env(@app, @config_key, value)
      end
    end)
  end

  test "application configuration rejects direct extension entries" do
    Application.put_env(@app, @config_key, entries: [SymphonyElixir.Workflow.Extensions.CodingPrDelivery])

    assert {:error, %{reason: :configured_entries_not_supported}} = Registry.validate()
  end

  test "application configuration rejects non-keyword values" do
    Application.put_env(@app, @config_key, %{sources: []})

    assert {:error, %{reason: :configured_registry_not_keyword, value_type: :map}} = Registry.validate()
  end

  test "application configuration rejects unsupported keys" do
    Application.put_env(@app, @config_key, sources: [], extra_sources: [])

    assert {:error, %{reason: :configured_registry_keys_not_supported, keys: [":extra_sources"]}} = Registry.validate()

    Application.put_env(@app, @config_key, sources: [], source_opts: [mode: :test])

    assert {:error, %{reason: :configured_registry_keys_not_supported, keys: [":source_opts"]}} = Registry.validate()
  end

  test "application configuration requires sources to be a list" do
    Application.put_env(@app, @config_key, sources: SymphonyElixir.AssemblyCatalog.WorkflowExtensions)

    assert {:error, %{reason: :configured_sources_not_list, value_type: :atom}} = Registry.validate()
  end
end
